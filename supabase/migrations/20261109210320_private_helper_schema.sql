-- Härtung: Interne Hilfsfunktionen aus dem API-Schema public in das nicht exponierte Schema private.
--
-- PostgREST stellt alle Funktionen in public als RPC bereit. Die Rechte-Prüfungen der Policies
-- (is_club_member usw.) und interne Helfer gehören nicht dazu. Policies und Trigger verweisen
-- intern über die Funktions-ID und funktionieren nach dem Verschieben unverändert. Funktionen, die
-- Helfer im Rumpf per Namen aufrufen, werden mit angepassten Verweisen neu angelegt (Definitionen
-- aus pg_get_functiondef der laufenden Datenbank). Trigger-Funktionen bleiben in public: Sie sind
-- über die API nicht aufrufbar, und handle_new_user hängt am Registrierungsablauf von Supabase Auth.
--
-- Neue Hilfsfunktionen für Policies gehören ab jetzt nach private.

create schema if not exists private;

-- Policies werden im Kontext von authenticated ausgewertet; das Schema ist nicht über die API erreichbar
grant usage on schema private to authenticated;

-- Verschieben (Rechte bleiben erhalten)
alter function public.is_club_member(p_club_id uuid) set schema private;
alter function public.is_club_organizer(p_club_id uuid) set schema private;
alter function public.shares_club_with(p_user_id uuid) set schema private;
alter function public.can_read_ticket_file(p_name text) set schema private;
alter function public.can_upload_ticket_file(p_name text) set schema private;
alter function public.can_delete_ticket_file(p_name text) set schema private;
alter function public.ticket_file_path(p_club_id uuid, p_request_id uuid) set schema private;
alter function public.ticket_file_request_id(p_name text) set schema private;
alter function public.ticket_round_is_open(p_round ticket_rounds) set schema private;
alter function public.promote_trip_waitlist(p_trip_id uuid) set schema private;
alter function public.format_berlin_datetime(p_ts timestamp with time zone) set schema private;
alter function public.trip_display_label(p_title text, p_transport transport_mode) set schema private;
alter function public.enqueue_notifications(p_user_ids uuid[], p_club_id uuid, p_kind notification_kind, p_title text, p_body text, p_url text) set schema private;

-- can_delete_ticket_file
CREATE OR REPLACE FUNCTION private.can_delete_ticket_file(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.ticket_requests r
    where r.id = private.ticket_file_request_id(p_name)
      and private.ticket_file_path(r.club_id, r.id) = p_name
      and private.is_club_organizer(r.club_id)
  );
$function$;

-- can_read_ticket_file
CREATE OR REPLACE FUNCTION private.can_read_ticket_file(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.ticket_requests r
    join public.ticket_rounds rd on rd.id = r.round_id
    where r.id = private.ticket_file_request_id(p_name)
      and private.ticket_file_path(r.club_id, r.id) = p_name
      and (
        private.is_club_organizer(r.club_id)
        or (
          r.requested_by = auth.uid()
          and r.status = 'allocated'
          and r.ticket_file_path = p_name
          and (not rd.download_requires_payment or r.payment_status = 'confirmed')
        )
      )
  );
$function$;

-- can_upload_ticket_file
CREATE OR REPLACE FUNCTION private.can_upload_ticket_file(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.ticket_requests r
    where r.id = private.ticket_file_request_id(p_name)
      and private.ticket_file_path(r.club_id, r.id) = p_name
      and r.status = 'allocated'
      and private.is_club_organizer(r.club_id)
  );
$function$;

-- attach_ticket_file
CREATE OR REPLACE FUNCTION public.attach_ticket_file(p_request_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.ticket_requests%rowtype;
  v_path text;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  if v_request.id is null or not private.is_club_organizer(v_request.club_id) then
    raise exception 'Nur Organisatoren können Tickets hinterlegen.';
  end if;

  if v_request.status <> 'allocated' then
    raise exception 'PDFs gibt es nur für zugeteilte Tickets.';
  end if;

  v_path := private.ticket_file_path(v_request.club_id, v_request.id);

  if not exists (
    select 1 from storage.objects where bucket_id = 'ticket-files' and name = v_path
  ) then
    raise exception 'Die Datei wurde nicht gefunden. Lade sie bitte erneut hoch.';
  end if;

  update public.ticket_requests
  set delivery_method = 'digital',
      pickup_location = null,
      pickup_at = null,
      ticket_file_path = v_path,
      ticket_file_uploaded_at = now()
  where id = p_request_id;

  return v_path;
end;
$function$;

-- auto_allocate_tickets
CREATE OR REPLACE FUNCTION public.auto_allocate_tickets(p_category_id uuid)
 RETURNS TABLE(allocated integer, waitlisted integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_club_id uuid;
  v_quota integer;
  v_free integer;
  v_allocated integer;
  v_waitlisted integer;
begin
  select club_id, quota into v_club_id, v_quota
  from public.ticket_categories
  where id = p_category_id
  for update;

  if v_club_id is null or not private.is_club_organizer(v_club_id) then
    raise exception 'Nur Organisatoren können Tickets zuteilen.';
  end if;

  if v_quota is null then
    raise exception 'Trag zuerst das Kontingent dieser Kategorie ein.';
  end if;

  select v_quota - count(*) into v_free
  from public.ticket_requests
  where category_id = p_category_id
    and status = 'allocated';

  with candidates as (
    select id
    from public.ticket_requests
    where category_id = p_category_id
      and status in ('requested', 'waitlist')
    order by created_at
    limit greatest(v_free, 0)
  )
  update public.ticket_requests r
  set status = 'allocated',
      status_changed_at = now()
  from candidates c
  where r.id = c.id;

  get diagnostics v_allocated = row_count;

  update public.ticket_requests
  set status = 'waitlist',
      status_changed_at = now()
  where category_id = p_category_id
    and status = 'requested';

  get diagnostics v_waitlisted = row_count;

  return query select v_allocated, v_waitlisted;
end;
$function$;

-- cancel_registrations_of_removed_member
CREATE OR REPLACE FUNCTION public.cancel_registrations_of_removed_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_trip_id uuid;
begin
  -- Beim Löschen des ganzen Fanclubs räumt die Kaskade auf
  if not exists (select 1 from public.clubs where id = old.club_id) then
    return old;
  end if;

  for v_trip_id in
    update public.trip_registrations
    set status = 'cancelled',
        status_changed_at = now()
    where club_id = old.club_id
      and user_id = old.user_id
      and status <> 'cancelled'
    returning trip_id
  loop
    perform private.promote_trip_waitlist(v_trip_id);
  end loop;

  update public.ticket_requests
  set status = 'cancelled',
      status_changed_at = now()
  where club_id = old.club_id
    and requested_by = old.user_id
    and status in ('requested', 'waitlist');

  return old;
end;
$function$;

-- cancel_ticket_request
CREATE OR REPLACE FUNCTION public.cancel_ticket_request(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.ticket_requests%rowtype;
  v_is_organizer boolean;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  v_is_organizer := v_request.id is not null and private.is_club_organizer(v_request.club_id);

  if v_request.id is null or (v_request.requested_by <> auth.uid() and not v_is_organizer) then
    raise exception 'Diese Ticketanfrage gibt es nicht.';
  end if;

  if v_request.status = 'cancelled' then
    return;
  end if;

  if not v_is_organizer and v_request.status not in ('requested', 'waitlist') then
    raise exception 'Ein zugeteiltes Ticket kann nur ein Organisator stornieren. Sprich ihn bitte an.';
  end if;

  update public.ticket_requests
  set status = 'cancelled',
      status_changed_at = now()
  where id = p_request_id;
end;
$function$;

-- cancel_trip_registration
CREATE OR REPLACE FUNCTION public.cancel_trip_registration(p_registration_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_trip_id uuid;
  v_club_id uuid;
  v_user_id uuid;
  v_status public.registration_status;
begin
  select trip_id, club_id, user_id into v_trip_id, v_club_id, v_user_id
  from public.trip_registrations
  where id = p_registration_id;

  if v_trip_id is null
    or (v_user_id <> auth.uid() and not private.is_club_organizer(v_club_id)) then
    raise exception 'Diese Anmeldung gibt es nicht.';
  end if;

  perform 1 from public.trips where id = v_trip_id for update;

  select status into v_status
  from public.trip_registrations
  where id = p_registration_id;

  if v_status = 'cancelled' then
    return;
  end if;

  update public.trip_registrations
  set status = 'cancelled',
      status_changed_at = now()
  where id = p_registration_id;

  perform private.promote_trip_waitlist(v_trip_id);
end;
$function$;

-- club_deletion_summary
CREATE OR REPLACE FUNCTION public.club_deletion_summary(p_club_id uuid)
 RETURNS TABLE(members integer, trips integer, ticket_rounds integer, open_payments integer, ticket_files integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    (select count(*) from public.club_members where club_id = p_club_id)::integer,
    (select count(*) from public.trips where club_id = p_club_id)::integer,
    (select count(*) from public.ticket_rounds where club_id = p_club_id)::integer,
    -- Bestätigte, nicht erstattete Zahlungen für kommende Spiele
    (
      (select count(*)
       from public.trip_registrations r
       join public.trips t on t.id = r.trip_id
       join public.away_games g on g.id = t.away_game_id
       where r.club_id = p_club_id
         and r.payment_status = 'confirmed'
         and (g.kickoff_at is null or g.kickoff_at > now()))
      +
      (select count(*)
       from public.ticket_requests q
       join public.ticket_rounds tr on tr.id = q.round_id
       join public.away_games g on g.id = tr.away_game_id
       where q.club_id = p_club_id
         and q.payment_status = 'confirmed'
         and (g.kickoff_at is null or g.kickoff_at > now()))
    )::integer,
    (select count(*) from public.ticket_requests where club_id = p_club_id and ticket_file_path is not null)::integer
  where private.is_club_organizer(p_club_id);
$function$;

-- confirm_all_trip_registrations
CREATE OR REPLACE FUNCTION public.confirm_all_trip_registrations(p_trip_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_club_id uuid;
  v_count integer;
begin
  select club_id into v_club_id
  from public.trips
  where id = p_trip_id;

  if v_club_id is null or not private.is_club_organizer(v_club_id) then
    raise exception 'Nur Organisatoren können Plätze bestätigen.';
  end if;

  update public.trip_registrations
  set status = 'confirmed',
      status_changed_at = now()
  where trip_id = p_trip_id
    and status = 'requested';

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

-- confirm_trip_registration
CREATE OR REPLACE FUNCTION public.confirm_trip_registration(p_registration_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_club_id uuid;
begin
  select club_id into v_club_id
  from public.trip_registrations
  where id = p_registration_id;

  if v_club_id is null or not private.is_club_organizer(v_club_id) then
    raise exception 'Nur Organisatoren können Plätze bestätigen.';
  end if;

  update public.trip_registrations
  set status = 'confirmed',
      status_changed_at = now()
  where id = p_registration_id
    and status = 'requested';

  if not found then
    raise exception 'Nur angefragte Anmeldungen können bestätigt werden.';
  end if;
end;
$function$;

-- detach_ticket_file
CREATE OR REPLACE FUNCTION public.detach_ticket_file(p_request_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.ticket_requests%rowtype;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  if v_request.id is null or not private.is_club_organizer(v_request.club_id) then
    raise exception 'Nur Organisatoren können Tickets hinterlegen.';
  end if;

  update public.ticket_requests
  set ticket_file_path = null,
      ticket_file_uploaded_at = null
  where id = p_request_id;

  return v_request.ticket_file_path;
end;
$function$;

-- ensure_away_game
CREATE OR REPLACE FUNCTION public.ensure_away_game(p_club_id uuid, p_openligadb_match_id integer, p_league_shortcut text, p_season integer, p_matchday integer, p_opponent_name text, p_kickoff_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  if not private.is_club_organizer(p_club_id) then
    raise exception 'Nur Organisatoren können Fahrten planen.';
  end if;

  insert into public.away_games (
    club_id, openligadb_match_id, league_shortcut, season, matchday, opponent_name, kickoff_at
  )
  values (
    p_club_id, p_openligadb_match_id, p_league_shortcut, p_season, p_matchday, btrim(p_opponent_name), p_kickoff_at
  )
  on conflict (club_id, openligadb_match_id) do update
  set matchday = excluded.matchday,
      opponent_name = excluded.opponent_name,
      kickoff_at = excluded.kickoff_at
  returning id into v_id;

  return v_id;
end;
$function$;

-- get_invite
CREATE OR REPLACE FUNCTION public.get_invite(p_token text)
 RETURNS TABLE(club_id uuid, club_name text, is_member boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select c.id, c.name, private.is_club_member(c.id)
  from public.club_invites i
  join public.clubs c on c.id = i.club_id
  where i.token = p_token
    and i.revoked_at is null;
$function$;

-- get_trip_stats
CREATE OR REPLACE FUNCTION public.get_trip_stats(p_club_id uuid)
 RETURNS TABLE(trip_id uuid, taken_seats integer, waitlist_count integer, my_registration_id uuid, my_status registration_status, my_waitlist_position integer, my_payment_status payment_status)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    t.id,
    (count(r.id) filter (where r.status in ('requested', 'confirmed')))::integer,
    (count(r.id) filter (where r.status = 'waitlist'))::integer,
    mine.id,
    mine.status,
    case when mine.status = 'waitlist' then (
      select count(*)::integer + 1
      from public.trip_registrations w
      where w.trip_id = t.id
        and w.status = 'waitlist'
        and (w.status_changed_at, w.created_at) < (mine.status_changed_at, mine.created_at)
    ) end,
    mine.payment_status
  from public.trips t
  left join public.trip_registrations r on r.trip_id = t.id
  left join public.trip_registrations mine on mine.trip_id = t.id and mine.user_id = auth.uid()
  where t.club_id = p_club_id
    and private.is_club_member(p_club_id)
  group by t.id, mine.id, mine.status, mine.status_changed_at, mine.created_at, mine.payment_status;
$function$;

-- notify_kickoff_change
CREATE OR REPLACE FUNCTION public.notify_kickoff_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  perform private.enqueue_notifications(
    v_users,
    new.club_id,
    case when old.kickoff_at is null then 'kickoff_scheduled' else 'kickoff_changed' end::public.notification_kind,
    case when old.kickoff_at is null then 'Anstoßzeit steht fest' else 'Anstoßzeit geändert' end,
    format('Das Spiel bei %s (%s. Spieltag) wird am %s angepfiffen.',
      new.opponent_name, new.matchday, private.format_berlin_datetime(new.kickoff_at)),
    format('/clubs/%s', new.club_id)
  );
  return new;
end;
$function$;

-- notify_ticket_request_change
CREATE OR REPLACE FUNCTION public.notify_ticket_request_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      perform private.enqueue_notifications(
        array[new.requested_by], new.club_id, 'ticket_allocated',
        'Ticket zugeteilt',
        format('%s bekommt ein Ticket (%s) für das Spiel bei %s. Bezahlen und Details findest du in der App.',
          new.holder_name, v_info.category, v_info.opponent_name),
        v_url
      );
    elsif new.status = 'rejected' then
      perform private.enqueue_notifications(
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
      perform private.enqueue_notifications(
        array[new.requested_by], new.club_id, 'ticket_delivery',
        'Dein Ticket ist da',
        format('Das Ticket-PDF für %s (Spiel bei %s) liegt in der App bereit.', new.holder_name, v_info.opponent_name),
        v_url
      );
    elsif new.delivery_method in ('pickup', 'box_office')
      and (new.delivery_method is distinct from old.delivery_method
        or new.pickup_location is distinct from old.pickup_location
        or new.pickup_at is distinct from old.pickup_at) then
      perform private.enqueue_notifications(
        array[new.requested_by], new.club_id, 'ticket_delivery',
        'So bekommst du dein Ticket',
        case new.delivery_method
          when 'pickup' then format('Ticket für %s (Spiel bei %s): Abholung %s%s.',
            new.holder_name, v_info.opponent_name, new.pickup_location,
            case when new.pickup_at is not null then ', ' || private.format_berlin_datetime(new.pickup_at) else '' end)
          else format('Das Ticket für %s liegt beim Spiel bei %s an der Gästekasse.', new.holder_name, v_info.opponent_name)
        end,
        v_url
      );
    end if;
  end if;

  return new;
end;
$function$;

-- notify_ticket_round_opened
CREATE OR REPLACE FUNCTION public.notify_ticket_round_opened()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_game record;
begin
  select opponent_name, matchday into v_game from public.away_games where id = new.away_game_id;

  perform private.enqueue_notifications(
    array(select user_id from public.club_members where club_id = new.club_id and user_id is distinct from new.created_by),
    new.club_id,
    'ticket_round_opened',
    'Ticketabfrage geöffnet',
    format('Für das Spiel bei %s (%s. Spieltag) kannst du jetzt Tickets anfragen%s.',
      v_game.opponent_name, v_game.matchday,
      case when new.request_deadline is not null then ', bis ' || private.format_berlin_datetime(new.request_deadline) else '' end),
    format('/clubs/%s/tickets/%s', new.club_id, new.id)
  );
  return new;
end;
$function$;

-- notify_trip_created
CREATE OR REPLACE FUNCTION public.notify_trip_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_game record;
begin
  select opponent_name, matchday into v_game from public.away_games where id = new.away_game_id;

  perform private.enqueue_notifications(
    array(select user_id from public.club_members where club_id = new.club_id and user_id is distinct from new.created_by),
    new.club_id,
    'trip_created',
    format('Neue Fahrt: %s', private.trip_display_label(new.title, new.transport)),
    format('Zum Spiel bei %s (%s. Spieltag)%s. Melde dich in der App an.',
      v_game.opponent_name, v_game.matchday,
      case when new.departure_at is not null then ', Abfahrt ' || private.format_berlin_datetime(new.departure_at) else '' end),
    format('/clubs/%s/trips/%s', new.club_id, new.id)
  );
  return new;
end;
$function$;

-- notify_trip_registration_change
CREATE OR REPLACE FUNCTION public.notify_trip_registration_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_trip record;
begin
  if old.status = 'waitlist' and new.status = 'requested' then
    select private.trip_display_label(t.title, t.transport) as label, g.opponent_name, g.matchday
    into v_trip
    from public.trips t
    join public.away_games g on g.id = t.away_game_id
    where t.id = new.trip_id;

    perform private.enqueue_notifications(
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
$function$;

-- regenerate_invite
CREATE OR REPLACE FUNCTION public.regenerate_invite(p_club_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_token text;
begin
  if not private.is_club_organizer(p_club_id) then
    raise exception 'Nur Organisatoren können den Einladungslink erneuern.';
  end if;

  update public.club_invites
  set revoked_at = now()
  where club_id = p_club_id
    and revoked_at is null;

  insert into public.club_invites (club_id, created_by)
  values (p_club_id, auth.uid())
  returning token into v_token;

  return v_token;
end;
$function$;

-- register_for_trip
CREATE OR REPLACE FUNCTION public.register_for_trip(p_trip_id uuid)
 RETURNS registration_status
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_existing public.registration_status;
  v_taken integer;
  v_status public.registration_status;
begin
  if v_user is null then
    raise exception 'Du bist nicht angemeldet.';
  end if;

  -- Sperre verhindert, dass zwei Personen gleichzeitig den letzten Platz bekommen
  select * into v_trip
  from public.trips
  where id = p_trip_id
  for update;

  if not found or not private.is_club_member(v_trip.club_id) then
    raise exception 'Diese Fahrt gibt es nicht.';
  end if;

  if v_trip.registration_deadline is not null and now() > v_trip.registration_deadline then
    raise exception 'Der Anmeldeschluss ist vorbei.';
  end if;

  if v_trip.departure_at is not null and now() >= v_trip.departure_at then
    raise exception 'Die Fahrt hat schon begonnen.';
  end if;

  select status into v_existing
  from public.trip_registrations
  where trip_id = p_trip_id
    and user_id = v_user;

  if v_existing is not null and v_existing <> 'cancelled' then
    return v_existing;
  end if;

  select count(*) into v_taken
  from public.trip_registrations
  where trip_id = p_trip_id
    and status in ('requested', 'confirmed');

  v_status := case
    when v_trip.capacity is null or v_taken < v_trip.capacity then 'requested'::public.registration_status
    else 'waitlist'::public.registration_status
  end;

  insert into public.trip_registrations (trip_id, club_id, user_id, status)
  values (p_trip_id, v_trip.club_id, v_user, v_status)
  on conflict (trip_id, user_id) do update
  set status = excluded.status,
      status_changed_at = now();

  return v_status;
end;
$function$;

-- request_ticket
CREATE OR REPLACE FUNCTION public.request_ticket(p_category_id uuid, p_holder_name text, p_membership_number text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_round_id uuid;
  v_round public.ticket_rounds%rowtype;
  v_count integer;
  v_number text := nullif(btrim(coalesce(p_membership_number, '')), '');
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Du bist nicht angemeldet.';
  end if;

  select round_id into v_round_id
  from public.ticket_categories
  where id = p_category_id;

  -- Sperre auf die Abfrage, damit der Höchstwert pro Mitglied nicht überlaufen kann
  select * into v_round
  from public.ticket_rounds
  where id = v_round_id
  for update;

  if not found or not private.is_club_member(v_round.club_id) then
    raise exception 'Diese Ticketkategorie gibt es nicht.';
  end if;

  if not private.ticket_round_is_open(v_round) then
    raise exception 'Die Ticketabfrage ist geschlossen.';
  end if;

  if v_round.membership_number_required and v_number is null then
    raise exception 'Für diese Abfrage brauchst du die Mitgliedsnummer des Inhabers.';
  end if;

  if v_round.max_tickets_per_member is not null then
    select count(*) into v_count
    from public.ticket_requests
    where round_id = v_round.id
      and requested_by = v_user
      and status not in ('cancelled', 'rejected');

    if v_count >= v_round.max_tickets_per_member then
      raise exception 'Du kannst höchstens % Tickets anfragen.', v_round.max_tickets_per_member;
    end if;
  end if;

  insert into public.ticket_requests (
    club_id, round_id, category_id, requested_by, holder_name, holder_membership_number
  )
  values (v_round.club_id, v_round.id, p_category_id, v_user, btrim(p_holder_name), v_number)
  returning id into v_id;

  return v_id;
end;
$function$;

-- set_payment_status
CREATE OR REPLACE FUNCTION public.set_payment_status(p_status payment_status, p_trip_registration_ids uuid[] DEFAULT '{}'::uuid[], p_ticket_request_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_trips integer;
  v_tickets integer;
begin
  if p_status = 'reported' then
    raise exception 'Zahlungen melden nur Mitglieder selbst.';
  end if;

  if cardinality(p_trip_registration_ids) + cardinality(p_ticket_request_ids) = 0
    or exists (
      select 1 from public.trip_registrations
      where id = any (p_trip_registration_ids) and not private.is_club_organizer(club_id)
    )
    or exists (
      select 1 from public.ticket_requests
      where id = any (p_ticket_request_ids) and not private.is_club_organizer(club_id)
    ) then
    raise exception 'Nur Organisatoren können Zahlungen bestätigen.';
  end if;

  if p_status = 'refunded' and (
    exists (
      select 1 from public.trip_registrations
      where id = any (p_trip_registration_ids) and payment_status not in ('confirmed', 'refunded')
    )
    or exists (
      select 1 from public.ticket_requests
      where id = any (p_ticket_request_ids) and payment_status not in ('confirmed', 'refunded')
    )
  ) then
    raise exception 'Erstatten kann man nur bestätigte Zahlungen.';
  end if;

  update public.trip_registrations r
  set payment_status = p_status,
      payment_status_changed_at = now(),
      payment_amount_cents = case when p_status = 'open' then null else coalesce(r.payment_amount_cents, t.price_cents) end
  from public.trips t
  where r.id = any (p_trip_registration_ids)
    and t.id = r.trip_id;

  get diagnostics v_trips = row_count;

  update public.ticket_requests q
  set payment_status = p_status,
      payment_status_changed_at = now(),
      payment_amount_cents = case when p_status = 'open' then null else coalesce(q.payment_amount_cents, c.price_cents) end
  from public.ticket_categories c
  where q.id = any (p_ticket_request_ids)
    and c.id = q.category_id;

  get diagnostics v_tickets = row_count;

  return v_trips + v_tickets;
end;
$function$;

-- set_ticket_delivery
CREATE OR REPLACE FUNCTION public.set_ticket_delivery(p_request_ids uuid[], p_method ticket_delivery_method, p_pickup_location text, p_pickup_at timestamp with time zone)
 RETURNS SETOF text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_location text := nullif(btrim(coalesce(p_pickup_location, '')), '');
begin
  if exists (
    select 1
    from public.ticket_requests r
    where r.id = any (p_request_ids)
      and not private.is_club_organizer(r.club_id)
  ) or cardinality(p_request_ids) = 0 then
    raise exception 'Nur Organisatoren können die Hinterlegung festlegen.';
  end if;

  if exists (
    select 1
    from public.ticket_requests r
    where r.id = any (p_request_ids)
      and r.status <> 'allocated'
  ) then
    raise exception 'Die Hinterlegung gibt es nur für zugeteilte Tickets.';
  end if;

  if p_method = 'pickup' and v_location is null then
    raise exception 'Bitte gib an, wo die Tickets abgeholt werden.';
  end if;

  return query
  with previous as (
    select id, ticket_file_path
    from public.ticket_requests
    where id = any (p_request_ids)
  ),
  updated as (
    update public.ticket_requests r
    set delivery_method = p_method,
        pickup_location = case when p_method = 'pickup' then v_location end,
        pickup_at = case when p_method = 'pickup' then p_pickup_at end,
        ticket_file_path = case when p_method = 'digital' then r.ticket_file_path end,
        ticket_file_uploaded_at = case when p_method = 'digital' then r.ticket_file_uploaded_at end
    where r.id = any (p_request_ids)
    returning r.id
  )
  select p.ticket_file_path
  from previous p
  join updated u on u.id = p.id
  where p_method <> 'digital'
    and p.ticket_file_path is not null;
end;
$function$;

-- set_ticket_request_status
CREATE OR REPLACE FUNCTION public.set_ticket_request_status(p_request_id uuid, p_status ticket_status)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.ticket_requests%rowtype;
  v_quota integer;
  v_allocated integer;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  if not found or not private.is_club_organizer(v_request.club_id) then
    raise exception 'Nur Organisatoren können Tickets zuteilen.';
  end if;

  if p_status = 'cancelled' then
    raise exception 'Zum Stornieren bitte die Stornierung verwenden.';
  end if;

  if v_request.status = p_status then
    return;
  end if;

  if p_status = 'allocated' then
    -- Sperre auf die Kategorie, damit das Kontingent nicht überbucht wird
    select quota into v_quota
    from public.ticket_categories
    where id = v_request.category_id
    for update;

    if v_quota is not null then
      select count(*) into v_allocated
      from public.ticket_requests
      where category_id = v_request.category_id
        and status = 'allocated';

      if v_allocated >= v_quota then
        raise exception 'Das Kontingent dieser Kategorie ist ausgeschöpft.';
      end if;
    end if;
  end if;

  update public.ticket_requests
  set status = p_status,
      status_changed_at = now()
  where id = p_request_id;
end;
$function$;

-- trips_promote_after_capacity_change
CREATE OR REPLACE FUNCTION public.trips_promote_after_capacity_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.capacity is distinct from old.capacity then
    perform private.promote_trip_waitlist(new.id);
  end if;
  return new;
end;
$function$;

-- update_ticket_request_holder
CREATE OR REPLACE FUNCTION public.update_ticket_request_holder(p_request_id uuid, p_holder_name text, p_membership_number text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.ticket_requests%rowtype;
  v_required boolean;
  v_number text := nullif(btrim(coalesce(p_membership_number, '')), '');
  v_is_organizer boolean;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  v_is_organizer := v_request.id is not null and private.is_club_organizer(v_request.club_id);

  if v_request.id is null or (v_request.requested_by <> auth.uid() and not v_is_organizer) then
    raise exception 'Diese Ticketanfrage gibt es nicht.';
  end if;

  if not v_is_organizer and v_request.status not in ('requested', 'waitlist') then
    raise exception 'Der Inhaber kann nur geändert werden, solange das Ticket noch nicht zugeteilt ist.';
  end if;

  select membership_number_required into v_required
  from public.ticket_rounds
  where id = v_request.round_id;

  if v_required and v_number is null then
    raise exception 'Für diese Abfrage brauchst du die Mitgliedsnummer des Inhabers.';
  end if;

  update public.ticket_requests
  set holder_name = btrim(p_holder_name),
      holder_membership_number = v_number
  where id = p_request_id;
end;
$function$;
