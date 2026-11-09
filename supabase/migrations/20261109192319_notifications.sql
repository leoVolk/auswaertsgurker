-- Etappe 7: Benachrichtigungen per E-Mail und Push
--
-- Trigger schreiben Benachrichtigungen (Text auf Deutsch, Link in die App) in den Postausgang
-- public.notifications. Der Server (server/utils/notify.ts) holt sie mit claim_notifications ab,
-- verschickt sie per E-Mail (falls nicht abbestellt) und Push und meldet das Ergebnis zurück.

-- ---------------------------------------------------------------------------
-- Einstellungen und Push-Abos
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column email_notifications boolean not null default true;

grant update (email_notifications) on public.profiles to authenticated;

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) between 1 and 2000),
  p256dh text not null check (char_length(p256dh) between 1 and 200),
  auth text not null check (char_length(auth) between 1 and 100),
  user_agent text check (char_length(user_agent) <= 500),
  created_at timestamptz not null default now()
);

create index push_subscriptions_user_id_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;
revoke insert, update, delete on public.push_subscriptions from anon, authenticated;

create policy "push_subscriptions_select_own"
  on public.push_subscriptions for select
  to authenticated
  using (user_id = (select auth.uid()));

-- Abo für dieses Gerät speichern; ein Gerät gehört immer dem zuletzt angemeldeten User
create function public.save_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Du bist nicht angemeldet.';
  end if;

  delete from public.push_subscriptions where endpoint = p_endpoint;

  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_user_agent, 500));
end;
$$;

create function public.delete_push_subscription(p_endpoint text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_subscriptions
  where endpoint = p_endpoint
    and user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Postausgang
-- ---------------------------------------------------------------------------

create type public.notification_kind as enum (
  'kickoff_scheduled',
  'kickoff_changed',
  'waitlist_promoted',
  'ticket_allocated',
  'ticket_rejected',
  'ticket_delivery',
  'trip_created',
  'ticket_round_opened'
);

create type public.notification_status as enum ('pending', 'sending', 'sent', 'failed');

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  club_id uuid references public.clubs (id) on delete cascade,
  kind public.notification_kind not null,
  title text not null,
  body text not null,
  -- Pfad in der App, z. B. /clubs/<id>/trips/<id>
  url text not null,
  status public.notification_status not null default 'pending',
  attempts integer not null default 0,
  claimed_at timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);

create index notifications_open_idx on public.notifications (created_at) where status in ('pending', 'sending');
create index notifications_user_id_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;
revoke insert, update, delete on public.notifications from anon, authenticated;

create policy "notifications_select_own"
  on public.notifications for select
  to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

-- z. B. „Sa., 21.11., 15:30 Uhr“ in Berliner Zeit
create function public.format_berlin_datetime(p_ts timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select (array['So.', 'Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.'])[extract(dow from p_ts at time zone 'Europe/Berlin')::integer + 1]
    || ', ' || to_char(p_ts at time zone 'Europe/Berlin', 'DD.MM., HH24:MI') || ' Uhr';
$$;

create function public.trip_display_label(p_title text, p_transport public.transport_mode)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_title, case p_transport when 'bus' then 'Bus' when 'train' then 'Zug' else 'Auto' end);
$$;

create function public.enqueue_notifications(
  p_user_ids uuid[],
  p_club_id uuid,
  p_kind public.notification_kind,
  p_title text,
  p_body text,
  p_url text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, club_id, kind, title, body, url)
  select distinct u, p_club_id, p_kind, p_title, p_body, p_url
  from unnest(p_user_ids) as u
  where u is not null;
$$;

-- ---------------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------------

-- Von der Warteliste nachgerückt
create function public.notify_trip_registration_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip record;
begin
  if old.status = 'waitlist' and new.status = 'requested' then
    select public.trip_display_label(t.title, t.transport) as label, g.opponent_name, g.matchday
    into v_trip
    from public.trips t
    join public.away_games g on g.id = t.away_game_id
    where t.id = new.trip_id;

    perform public.enqueue_notifications(
      array[new.user_id],
      new.club_id,
      'waitlist_promoted',
      'Du bist nachgerückt',
      format('Für „%s“ zum Spiel bei %s (%s. Spieltag) hast du jetzt einen Platz. Ein Organisator bestätigt ihn noch.',
        v_trip.label, v_trip.opponent_name, v_trip.matchday),
      format('/clubs/%s/trips/%s', new.club_id, new.trip_id)
    );
  end if;
  return new;
end;
$$;

create trigger trip_registrations_notify
  after update of status on public.trip_registrations
  for each row execute function public.notify_trip_registration_change();

-- Ticket zugeteilt/abgelehnt, PDF da, Hinterlegung festgelegt
create function public.notify_ticket_request_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_info record;
  v_url text := format('/clubs/%s/tickets/%s', new.club_id, new.round_id);
begin
  select g.opponent_name, c.name as category
  into v_info
  from public.ticket_rounds r
  join public.away_games g on g.id = r.away_game_id
  join public.ticket_categories c on c.id = new.category_id
  where r.id = new.round_id;

  if new.status is distinct from old.status then
    if new.status = 'allocated' then
      perform public.enqueue_notifications(
        array[new.requested_by], new.club_id, 'ticket_allocated',
        'Ticket zugeteilt',
        format('%s bekommt ein Ticket (%s) für das Spiel bei %s. Bezahlen und Details findest du in der App.',
          new.holder_name, v_info.category, v_info.opponent_name),
        v_url
      );
    elsif new.status = 'rejected' then
      perform public.enqueue_notifications(
        array[new.requested_by], new.club_id, 'ticket_rejected',
        'Leider kein Ticket',
        format('Für %s gibt es beim Spiel bei %s leider kein Ticket aus dem Kontingent.',
          new.holder_name, v_info.opponent_name),
        v_url
      );
    end if;
  end if;

  if new.status = 'allocated' then
    if new.ticket_file_path is not null and old.ticket_file_path is null then
      perform public.enqueue_notifications(
        array[new.requested_by], new.club_id, 'ticket_delivery',
        'Dein Ticket ist da',
        format('Das Ticket-PDF für %s (Spiel bei %s) liegt in der App bereit.', new.holder_name, v_info.opponent_name),
        v_url
      );
    elsif new.delivery_method in ('pickup', 'box_office')
      and (new.delivery_method is distinct from old.delivery_method
        or new.pickup_location is distinct from old.pickup_location
        or new.pickup_at is distinct from old.pickup_at) then
      perform public.enqueue_notifications(
        array[new.requested_by], new.club_id, 'ticket_delivery',
        'So bekommst du dein Ticket',
        case new.delivery_method
          when 'pickup' then format('Ticket für %s (Spiel bei %s): Abholung %s%s.',
            new.holder_name, v_info.opponent_name, new.pickup_location,
            case when new.pickup_at is not null then ', ' || public.format_berlin_datetime(new.pickup_at) else '' end)
          else format('Das Ticket für %s liegt beim Spiel bei %s an der Gästekasse.', new.holder_name, v_info.opponent_name)
        end,
        v_url
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger ticket_requests_notify
  after update on public.ticket_requests
  for each row execute function public.notify_ticket_request_change();

-- Neue Fahrt an alle Mitglieder (außer der Person, die sie angelegt hat)
create function public.notify_trip_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game record;
begin
  select opponent_name, matchday into v_game from public.away_games where id = new.away_game_id;

  perform public.enqueue_notifications(
    array(select user_id from public.club_members where club_id = new.club_id and user_id is distinct from new.created_by),
    new.club_id,
    'trip_created',
    format('Neue Fahrt: %s', public.trip_display_label(new.title, new.transport)),
    format('Zum Spiel bei %s (%s. Spieltag)%s. Melde dich in der App an.',
      v_game.opponent_name, v_game.matchday,
      case when new.departure_at is not null then ', Abfahrt ' || public.format_berlin_datetime(new.departure_at) else '' end),
    format('/clubs/%s/trips/%s', new.club_id, new.id)
  );
  return new;
end;
$$;

create trigger trips_notify_created
  after insert on public.trips
  for each row execute function public.notify_trip_created();

-- Neue Ticketabfrage an alle Mitglieder (außer der Person, die sie geöffnet hat)
create function public.notify_ticket_round_opened()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game record;
begin
  select opponent_name, matchday into v_game from public.away_games where id = new.away_game_id;

  perform public.enqueue_notifications(
    array(select user_id from public.club_members where club_id = new.club_id and user_id is distinct from new.created_by),
    new.club_id,
    'ticket_round_opened',
    'Ticketabfrage geöffnet',
    format('Für das Spiel bei %s (%s. Spieltag) kannst du jetzt Tickets anfragen%s.',
      v_game.opponent_name, v_game.matchday,
      case when new.request_deadline is not null then ', bis ' || public.format_berlin_datetime(new.request_deadline) else '' end),
    format('/clubs/%s/tickets/%s', new.club_id, new.id)
  );
  return new;
end;
$$;

create trigger ticket_rounds_notify_opened
  after insert on public.ticket_rounds
  for each row execute function public.notify_ticket_round_opened();

-- Anstoßzeit steht fest oder hat sich geändert: alle mit Anmeldung oder Ticketanfrage zum Spiel
create function public.notify_kickoff_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_users uuid[];
begin
  -- Nur für kommende Spiele; Nachträge nach dem Spiel (z. B. durch die Löschfrist) nicht melden
  if new.kickoff_at is null
    or new.kickoff_at is not distinct from old.kickoff_at
    or new.kickoff_at <= now() then
    return new;
  end if;

  select array_agg(distinct u) into v_users
  from (
    select r.user_id as u
    from public.trip_registrations r
    join public.trips t on t.id = r.trip_id
    where t.away_game_id = new.id
      and r.status in ('requested', 'confirmed', 'waitlist')
    union
    select q.requested_by
    from public.ticket_requests q
    join public.ticket_rounds tr on tr.id = q.round_id
    where tr.away_game_id = new.id
      and q.status in ('requested', 'allocated', 'waitlist')
  ) s;

  if v_users is null then
    return new;
  end if;

  perform public.enqueue_notifications(
    v_users,
    new.club_id,
    case when old.kickoff_at is null then 'kickoff_scheduled' else 'kickoff_changed' end::public.notification_kind,
    case when old.kickoff_at is null then 'Anstoßzeit steht fest' else 'Anstoßzeit geändert' end,
    format('Das Spiel bei %s (%s. Spieltag) wird am %s angepfiffen.',
      new.opponent_name, new.matchday, public.format_berlin_datetime(new.kickoff_at)),
    format('/clubs/%s', new.club_id)
  );
  return new;
end;
$$;

create trigger away_games_notify_kickoff
  after update of kickoff_at on public.away_games
  for each row execute function public.notify_kickoff_change();

-- ---------------------------------------------------------------------------
-- Versand (nur Server mit Secret Key)
-- ---------------------------------------------------------------------------

-- Offene Benachrichtigungen reservieren; hängengebliebene nach 10 Minuten erneut, höchstens 5 Versuche
create function public.claim_notifications(p_limit integer)
returns setof public.notifications
language sql
security definer
set search_path = ''
as $$
  update public.notifications n
  set status = 'sending',
      claimed_at = now(),
      attempts = n.attempts + 1
  where n.id in (
    select id
    from public.notifications
    where (status = 'pending' or (status = 'sending' and claimed_at < now() - interval '10 minutes'))
      and attempts < 5
    order by created_at
    limit p_limit
    for update skip locked
  )
  returning n.*;
$$;

create function public.complete_notifications(p_ids uuid[], p_success boolean, p_error text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.notifications
  set status = case
        when p_success then 'sent'::public.notification_status
        when attempts >= 5 then 'failed'::public.notification_status
        else 'pending'::public.notification_status
      end,
      sent_at = case when p_success then now() end,
      last_error = case when p_success then null else left(p_error, 500) end
  where id = any (p_ids);
$$;

create function public.notification_recipients(p_user_ids uuid[])
returns table (user_id uuid, email text, display_name text, email_notifications boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, u.email::text, p.display_name, p.email_notifications
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = any (p_user_ids);
$$;

-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------

revoke execute on function
  public.save_push_subscription(text, text, text, text),
  public.delete_push_subscription(text),
  public.format_berlin_datetime(timestamptz),
  public.trip_display_label(text, public.transport_mode),
  public.enqueue_notifications(uuid[], uuid, public.notification_kind, text, text, text),
  public.notify_trip_registration_change(),
  public.notify_ticket_request_change(),
  public.notify_trip_created(),
  public.notify_ticket_round_opened(),
  public.notify_kickoff_change(),
  public.claim_notifications(integer),
  public.complete_notifications(uuid[], boolean, text),
  public.notification_recipients(uuid[])
from public, anon, authenticated;

grant execute on function
  public.save_push_subscription(text, text, text, text),
  public.delete_push_subscription(text)
to authenticated;

grant execute on function
  public.claim_notifications(integer),
  public.complete_notifications(uuid[], boolean, text),
  public.notification_recipients(uuid[])
to service_role;
