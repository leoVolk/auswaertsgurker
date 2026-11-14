-- Tickets kommen nur noch als PDF (keine Abholung, keine Gästekasse mehr), jede Ticketanfrage braucht
-- eine Vereinsmitgliedsnummer, und jede Person kann ihre eigene Nummer im Profil speichern.

-- ---------------------------------------------------------------------------
-- Hinterlegungsart entfernen
-- ---------------------------------------------------------------------------

drop function public.set_ticket_delivery(uuid[], public.ticket_delivery_method, text, timestamptz);

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
  set ticket_file_path = v_path,
      ticket_file_uploaded_at = now()
  where id = p_request_id;

  return v_path;
end;
$function$;

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

  if new.status = 'allocated' and new.ticket_file_path is not null and old.ticket_file_path is null then
    perform private.enqueue_notifications(
      array[new.requested_by], new.club_id, 'ticket_delivery',
      'Dein Ticket ist da',
      format('Das Ticket-PDF für %s (Spiel bei %s) liegt in der App bereit.', new.holder_name, v_info.opponent_name),
      v_url
    );
  end if;

  return new;
end;
$function$;

alter table public.ticket_requests
  drop column delivery_method,
  drop column pickup_location,
  drop column pickup_at;

drop type public.ticket_delivery_method;

-- ---------------------------------------------------------------------------
-- Mitgliedsnummer immer verpflichtend
-- ---------------------------------------------------------------------------

alter table public.ticket_rounds drop column membership_number_required;

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

  if v_number is null then
    raise exception 'Bitte gib die Mitgliedsnummer des Inhabers an.';
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

CREATE OR REPLACE FUNCTION public.update_ticket_request_holder(p_request_id uuid, p_holder_name text, p_membership_number text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.ticket_requests%rowtype;
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

  if v_number is null then
    raise exception 'Bitte gib die Mitgliedsnummer des Inhabers an.';
  end if;

  update public.ticket_requests
  set holder_name = btrim(p_holder_name),
      holder_membership_number = v_number
  where id = p_request_id;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Eigene Mitgliedsnummer
-- ---------------------------------------------------------------------------

-- Eigene Tabelle statt Spalte in profiles: Profile lesen alle Mitglieder gemeinsamer Fanclubs,
-- die Nummer soll nur die Person selbst sehen. Pro Person gibt es genau eine Nummer.
create table public.membership_numbers (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  membership_number text not null check (char_length(membership_number) between 1 and 40),
  updated_at timestamptz not null default now()
);

comment on table public.membership_numbers is
  'Eigene Vereinsmitgliedsnummer zum Vorausfüllen von Ticketanfragen; nur für die Person selbst lesbar';

alter table public.membership_numbers enable row level security;

create policy "membership_numbers_select_own"
  on public.membership_numbers for select
  to authenticated
  using (user_id = (select auth.uid()));

-- Schreiben nur über set_my_membership_number
revoke all on public.membership_numbers from anon, authenticated;
grant select on public.membership_numbers to authenticated;

create function public.set_my_membership_number(p_membership_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_number text := nullif(btrim(coalesce(p_membership_number, '')), '');
begin
  if v_user is null then
    raise exception 'Du bist nicht angemeldet.';
  end if;

  -- Leere Eingabe löscht die gespeicherte Nummer
  if v_number is null then
    delete from public.membership_numbers where user_id = v_user;
    return;
  end if;

  if char_length(v_number) > 40 then
    raise exception 'Die Mitgliedsnummer darf höchstens 40 Zeichen lang sein.';
  end if;

  insert into public.membership_numbers (user_id, membership_number)
  values (v_user, v_number)
  on conflict (user_id) do update
    set membership_number = excluded.membership_number,
        updated_at = now();
end;
$$;

revoke execute on function public.set_my_membership_number(text) from public, anon;
grant execute on function public.set_my_membership_number(text) to authenticated;
