-- Etappe 3: Anmeldung zu Fahrten mit Warteliste
--
-- Ablauf: Anmeldung -> requested (belegt einen Platz) -> Organisator bestätigt -> confirmed.
-- Ist die Fahrt voll, landet man auf der waitlist. Wird ein Platz frei (Absage, mehr Plätze,
-- Mitglied entfernt), rückt der Erste der Warteliste auf requested nach.

create type public.registration_status as enum ('requested', 'confirmed', 'waitlist', 'cancelled');

-- Ziel für den zusammengesetzten Fremdschlüssel aus trip_registrations
alter table public.trips add constraint trips_id_club_id_key unique (id, club_id);

create table public.trip_registrations (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null,
  club_id uuid not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status public.registration_status not null,
  -- Reihenfolge der Warteliste
  status_changed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (trip_id, user_id),
  foreign key (trip_id, club_id) references public.trips (id, club_id) on delete cascade
);

create index trip_registrations_trip_status_idx
  on public.trip_registrations (trip_id, status, status_changed_at);
create index trip_registrations_user_id_idx on public.trip_registrations (user_id);

-- ---------------------------------------------------------------------------
-- Interne Funktionen (nicht per API aufrufbar)
-- ---------------------------------------------------------------------------

-- Freie Plätze mit der Warteliste auffüllen. Erwartet, dass die Fahrt gesperrt werden darf.
create function public.promote_trip_waitlist(p_trip_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_capacity integer;
  v_taken integer;
begin
  select capacity into v_capacity
  from public.trips
  where id = p_trip_id
  for update;

  if not found then
    return;
  end if;

  select count(*) into v_taken
  from public.trip_registrations
  where trip_id = p_trip_id
    and status in ('requested', 'confirmed');

  if v_capacity is not null and v_taken >= v_capacity then
    return;
  end if;

  update public.trip_registrations
  set status = 'requested',
      status_changed_at = now()
  where id in (
    select id
    from public.trip_registrations
    where trip_id = p_trip_id
      and status = 'waitlist'
    order by status_changed_at, created_at
    limit case when v_capacity is null then null else v_capacity - v_taken end
  );
end;
$$;

-- Mehr Plätze -> Warteliste rückt nach
create function public.trips_promote_after_capacity_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.capacity is distinct from old.capacity then
    perform public.promote_trip_waitlist(new.id);
  end if;
  return new;
end;
$$;

create trigger trips_capacity_changed
  after update of capacity on public.trips
  for each row execute function public.trips_promote_after_capacity_change();

-- Mitglied verlässt den Fanclub -> seine Anmeldungen werden storniert
create function public.cancel_registrations_of_removed_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
    perform public.promote_trip_waitlist(v_trip_id);
  end loop;

  return old;
end;
$$;

create trigger club_members_cancel_registrations
  after delete on public.club_members
  for each row execute function public.cancel_registrations_of_removed_member();

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Für eine Fahrt anmelden; liefert den neuen Status (requested oder waitlist)
create function public.register_for_trip(p_trip_id uuid)
returns public.registration_status
language plpgsql
security definer
set search_path = ''
as $$
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

  if not found or not public.is_club_member(v_trip.club_id) then
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
$$;

-- Absagen: eigene Anmeldung oder als Organisator; die Warteliste rückt nach
create function public.cancel_trip_registration(p_registration_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
    or (v_user_id <> auth.uid() and not public.is_club_organizer(v_club_id)) then
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

  perform public.promote_trip_waitlist(v_trip_id);
end;
$$;

-- Platz bestätigen (nur Organisatoren, nur angefragte Anmeldungen)
create function public.confirm_trip_registration(p_registration_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club_id uuid;
begin
  select club_id into v_club_id
  from public.trip_registrations
  where id = p_registration_id;

  if v_club_id is null or not public.is_club_organizer(v_club_id) then
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
$$;

-- Alle offenen Anfragen einer Fahrt bestätigen; liefert die Anzahl
create function public.confirm_all_trip_registrations(p_trip_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club_id uuid;
  v_count integer;
begin
  select club_id into v_club_id
  from public.trips
  where id = p_trip_id;

  if v_club_id is null or not public.is_club_organizer(v_club_id) then
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
$$;

-- Belegung aller Fahrten eines Fanclubs plus eigener Status. Mitglieder sehen so die
-- Zahlen, ohne die Anmeldungen anderer lesen zu dürfen.
create function public.get_trip_stats(p_club_id uuid)
returns table (
  trip_id uuid,
  taken_seats integer,
  waitlist_count integer,
  my_registration_id uuid,
  my_status public.registration_status,
  my_waitlist_position integer
)
language sql
stable
security definer
set search_path = ''
as $$
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
    ) end
  from public.trips t
  left join public.trip_registrations r on r.trip_id = t.id
  left join public.trip_registrations mine on mine.trip_id = t.id and mine.user_id = auth.uid()
  where t.club_id = p_club_id
    and public.is_club_member(p_club_id)
  group by t.id, mine.id, mine.status, mine.status_changed_at, mine.created_at;
$$;

-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------

revoke execute on function
  public.promote_trip_waitlist(uuid),
  public.trips_promote_after_capacity_change(),
  public.cancel_registrations_of_removed_member(),
  public.register_for_trip(uuid),
  public.cancel_trip_registration(uuid),
  public.confirm_trip_registration(uuid),
  public.confirm_all_trip_registrations(uuid),
  public.get_trip_stats(uuid)
from public, anon, authenticated;

grant execute on function
  public.register_for_trip(uuid),
  public.cancel_trip_registration(uuid),
  public.confirm_trip_registration(uuid),
  public.confirm_all_trip_registrations(uuid),
  public.get_trip_stats(uuid)
to authenticated;

-- trip_registrations: eigene Anmeldungen und (für Organisatoren) alle des Fanclubs lesen;
-- Änderungen nur über die RPCs
alter table public.trip_registrations enable row level security;

revoke insert, update, delete on public.trip_registrations from anon, authenticated;

create policy "trip_registrations_select_own_or_organizers"
  on public.trip_registrations for select
  to authenticated
  using (user_id = (select auth.uid()) or public.is_club_organizer(club_id));
