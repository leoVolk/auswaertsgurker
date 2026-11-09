-- Etappe 4: Ticketabfragen aus dem Fanclub-Kontingent
--
-- Pro Auswärtsspiel eine Ticketabfrage mit Kategorien (Preis, Kontingent). Jedes Ticket ist eine
-- eigene Anfrage mit Inhabername. Organisatoren teilen zu; es gibt kein automatisches Nachrücken.

create type public.ticket_status as enum ('requested', 'allocated', 'waitlist', 'rejected', 'cancelled');

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

create table public.ticket_rounds (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs (id) on delete cascade,
  away_game_id uuid not null,
  request_deadline timestamptz,
  max_tickets_per_member integer check (max_tickets_per_member between 1 and 20),
  membership_number_required boolean not null default false,
  notes text check (char_length(notes) between 1 and 2000),
  -- Vorzeitig von Organisatoren geschlossen
  closed_at timestamptz,
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  -- Eine Ticketabfrage pro Auswärtsspiel
  unique (away_game_id),
  unique (id, club_id),
  foreign key (away_game_id, club_id) references public.away_games (id, club_id) on delete cascade
);

create table public.ticket_categories (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null,
  club_id uuid not null,
  name text not null check (char_length(name) between 1 and 60),
  price_cents integer not null check (price_cents between 0 and 100000),
  -- null = Kontingent noch nicht bekannt
  quota integer check (quota between 0 and 10000),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (id, round_id),
  foreign key (round_id, club_id) references public.ticket_rounds (id, club_id) on delete cascade
);

create index ticket_categories_round_id_idx on public.ticket_categories (round_id);

create table public.ticket_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  round_id uuid not null,
  category_id uuid not null,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  holder_name text not null check (char_length(holder_name) between 2 and 80),
  -- Vereinsmitgliedsnummer; wird 30 Tage nach dem Spiel gelöscht (Etappe 6)
  holder_membership_number text check (char_length(holder_membership_number) between 1 and 40),
  status public.ticket_status not null default 'requested',
  status_changed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (round_id, club_id) references public.ticket_rounds (id, club_id) on delete cascade,
  -- Kategorie muss zur selben Abfrage gehören; NO ACTION, damit Kaskaden beim Löschen der
  -- Abfrage funktionieren, eine Kategorie mit Anfragen aber nicht einzeln gelöscht werden kann
  foreign key (category_id, round_id) references public.ticket_categories (id, round_id)
);

create index ticket_requests_round_id_idx on public.ticket_requests (round_id);
create index ticket_requests_category_status_idx on public.ticket_requests (category_id, status);
create index ticket_requests_requested_by_idx on public.ticket_requests (requested_by);

-- ---------------------------------------------------------------------------
-- Hilfsfunktion
-- ---------------------------------------------------------------------------

create function public.ticket_round_is_open(p_round public.ticket_rounds)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_round.closed_at is null
    and (p_round.request_deadline is null or now() <= p_round.request_deadline);
$$;

-- ---------------------------------------------------------------------------
-- RPCs für Mitglieder
-- ---------------------------------------------------------------------------

-- Ticket anfragen
create function public.request_ticket(
  p_category_id uuid,
  p_holder_name text,
  p_membership_number text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
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

  if not found or not public.is_club_member(v_round.club_id) then
    raise exception 'Diese Ticketkategorie gibt es nicht.';
  end if;

  if not public.ticket_round_is_open(v_round) then
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
$$;

-- Inhaber ändern: eigene Anfrage, solange noch nicht zugeteilt; Organisatoren immer
create function public.update_ticket_request_holder(
  p_request_id uuid,
  p_holder_name text,
  p_membership_number text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.ticket_requests%rowtype;
  v_required boolean;
  v_number text := nullif(btrim(coalesce(p_membership_number, '')), '');
  v_is_organizer boolean;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  v_is_organizer := v_request.id is not null and public.is_club_organizer(v_request.club_id);

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
$$;

-- Stornieren: eigene Anfrage, solange angefragt oder auf der Warteliste; Organisatoren immer
create function public.cancel_ticket_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.ticket_requests%rowtype;
  v_is_organizer boolean;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  v_is_organizer := v_request.id is not null and public.is_club_organizer(v_request.club_id);

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
$$;

-- ---------------------------------------------------------------------------
-- RPCs für Organisatoren
-- ---------------------------------------------------------------------------

-- Status einer Anfrage setzen (Stornieren über cancel_ticket_request)
create function public.set_ticket_request_status(p_request_id uuid, p_status public.ticket_status)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.ticket_requests%rowtype;
  v_quota integer;
  v_allocated integer;
begin
  select * into v_request
  from public.ticket_requests
  where id = p_request_id;

  if not found or not public.is_club_organizer(v_request.club_id) then
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
$$;

-- Kontingent einer Kategorie nach Anfragezeitpunkt verteilen, Rest auf die Warteliste
create function public.auto_allocate_tickets(p_category_id uuid)
returns table (allocated integer, waitlisted integer)
language plpgsql
security definer
set search_path = ''
as $$
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

  if v_club_id is null or not public.is_club_organizer(v_club_id) then
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
$$;

-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------

revoke execute on function
  public.ticket_round_is_open(public.ticket_rounds),
  public.request_ticket(uuid, text, text),
  public.update_ticket_request_holder(uuid, text, text),
  public.cancel_ticket_request(uuid),
  public.set_ticket_request_status(uuid, public.ticket_status),
  public.auto_allocate_tickets(uuid)
from public, anon, authenticated;

grant execute on function
  public.request_ticket(uuid, text, text),
  public.update_ticket_request_holder(uuid, text, text),
  public.cancel_ticket_request(uuid),
  public.set_ticket_request_status(uuid, public.ticket_status),
  public.auto_allocate_tickets(uuid)
to authenticated;

-- ticket_rounds: Mitglieder lesen, Organisatoren schreiben
alter table public.ticket_rounds enable row level security;

revoke insert, update, delete on public.ticket_rounds from anon, authenticated;
grant insert (
  club_id, away_game_id, request_deadline, max_tickets_per_member, membership_number_required, notes
) on public.ticket_rounds to authenticated;
grant update (
  request_deadline, max_tickets_per_member, membership_number_required, notes, closed_at
) on public.ticket_rounds to authenticated;
grant delete on public.ticket_rounds to authenticated;

create policy "ticket_rounds_select_members"
  on public.ticket_rounds for select
  to authenticated
  using (public.is_club_member(club_id));

create policy "ticket_rounds_insert_organizers"
  on public.ticket_rounds for insert
  to authenticated
  with check (public.is_club_organizer(club_id));

create policy "ticket_rounds_update_organizers"
  on public.ticket_rounds for update
  to authenticated
  using (public.is_club_organizer(club_id))
  with check (public.is_club_organizer(club_id));

create policy "ticket_rounds_delete_organizers"
  on public.ticket_rounds for delete
  to authenticated
  using (public.is_club_organizer(club_id));

-- ticket_categories: Mitglieder lesen, Organisatoren schreiben
alter table public.ticket_categories enable row level security;

revoke insert, update, delete on public.ticket_categories from anon, authenticated;
grant insert (round_id, club_id, name, price_cents, quota, sort_order) on public.ticket_categories to authenticated;
grant update (name, price_cents, quota, sort_order) on public.ticket_categories to authenticated;
grant delete on public.ticket_categories to authenticated;

create policy "ticket_categories_select_members"
  on public.ticket_categories for select
  to authenticated
  using (public.is_club_member(club_id));

create policy "ticket_categories_insert_organizers"
  on public.ticket_categories for insert
  to authenticated
  with check (public.is_club_organizer(club_id));

create policy "ticket_categories_update_organizers"
  on public.ticket_categories for update
  to authenticated
  using (public.is_club_organizer(club_id))
  with check (public.is_club_organizer(club_id));

create policy "ticket_categories_delete_organizers"
  on public.ticket_categories for delete
  to authenticated
  using (public.is_club_organizer(club_id));

-- ticket_requests: nur anfragende Person und Organisatoren; Änderungen nur über RPCs
alter table public.ticket_requests enable row level security;

revoke insert, update, delete on public.ticket_requests from anon, authenticated;

create policy "ticket_requests_select_own_or_organizers"
  on public.ticket_requests for select
  to authenticated
  using (requested_by = (select auth.uid()) or public.is_club_organizer(club_id));
