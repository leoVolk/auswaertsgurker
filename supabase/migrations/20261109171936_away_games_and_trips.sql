-- Etappe 2: Verein des Fanclubs, Auswärtsspiele und Fahrten

-- ---------------------------------------------------------------------------
-- Verein des Fanclubs (Daten aus OpenLigaDB)
-- ---------------------------------------------------------------------------

alter table public.clubs
  add column league_shortcut text check (league_shortcut in ('bl1', 'bl2', 'bl3')),
  add column team_id integer check (team_id > 0),
  add column team_name text check (char_length(team_name) between 1 and 100),
  add constraint clubs_team_complete check (
    (league_shortcut is null and team_id is null and team_name is null)
    or (league_shortcut is not null and team_id is not null and team_name is not null)
  );

comment on column public.clubs.team_id is 'teamId aus OpenLigaDB';

grant update (league_shortcut, team_id, team_name) on public.clubs to authenticated;

-- ---------------------------------------------------------------------------
-- Auswärtsspiele: Anker für Fahrten (und später Ticketabfragen)
-- ---------------------------------------------------------------------------

create table public.away_games (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs (id) on delete cascade,
  openligadb_match_id integer not null check (openligadb_match_id > 0),
  league_shortcut text not null check (league_shortcut in ('bl1', 'bl2', 'bl3')),
  season integer not null check (season between 2000 and 2100),
  matchday integer not null check (matchday > 0),
  opponent_name text not null check (char_length(opponent_name) between 1 and 100),
  -- null = Spieltag noch nicht terminiert ("Termin offen")
  kickoff_at timestamptz,
  created_at timestamptz not null default now(),
  unique (club_id, openligadb_match_id),
  -- Ziel für den zusammengesetzten Fremdschlüssel aus trips
  unique (id, club_id)
);

-- Auswärtsspiel anlegen oder dessen Spieldaten aktualisieren
create function public.ensure_away_game(
  p_club_id uuid,
  p_openligadb_match_id integer,
  p_league_shortcut text,
  p_season integer,
  p_matchday integer,
  p_opponent_name text,
  p_kickoff_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not public.is_club_organizer(p_club_id) then
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
$$;

-- ---------------------------------------------------------------------------
-- Fahrten
-- ---------------------------------------------------------------------------

create type public.transport_mode as enum ('bus', 'train', 'car');

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs (id) on delete cascade,
  away_game_id uuid not null,
  transport public.transport_mode not null,
  title text check (char_length(title) between 1 and 80),
  departure_at timestamptz,
  meeting_point text check (char_length(meeting_point) between 1 and 200),
  -- null = unbegrenzt
  capacity integer check (capacity between 1 and 1000),
  -- Kosten pro Person in Cent; null = noch offen
  price_cents integer check (price_cents between 0 and 100000),
  registration_deadline timestamptz,
  notes text check (char_length(notes) between 1 and 2000),
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  -- Eine Fahrt kann nur an einem Auswärtsspiel desselben Fanclubs hängen
  foreign key (away_game_id, club_id) references public.away_games (id, club_id) on delete cascade,
  check (registration_deadline is null or departure_at is null or registration_deadline <= departure_at)
);

create index trips_club_id_idx on public.trips (club_id);
create index trips_away_game_id_idx on public.trips (away_game_id);

-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------

revoke execute on function
  public.ensure_away_game(uuid, integer, text, integer, integer, text, timestamptz)
from public, anon, authenticated;

grant execute on function
  public.ensure_away_game(uuid, integer, text, integer, integer, text, timestamptz)
to authenticated;

-- away_games: lesen für Mitglieder, schreiben nur über ensure_away_game
alter table public.away_games enable row level security;

revoke insert, update, delete on public.away_games from anon, authenticated;

create policy "away_games_select_members"
  on public.away_games for select
  to authenticated
  using (public.is_club_member(club_id));

-- trips: Mitglieder lesen, Organisatoren legen an, ändern und löschen
alter table public.trips enable row level security;

revoke insert, update, delete on public.trips from anon, authenticated;

grant insert (
  club_id, away_game_id, transport, title, departure_at, meeting_point,
  capacity, price_cents, registration_deadline, notes
) on public.trips to authenticated;

grant update (
  transport, title, departure_at, meeting_point,
  capacity, price_cents, registration_deadline, notes
) on public.trips to authenticated;

grant delete on public.trips to authenticated;

create policy "trips_select_members"
  on public.trips for select
  to authenticated
  using (public.is_club_member(club_id));

create policy "trips_insert_organizers"
  on public.trips for insert
  to authenticated
  with check (public.is_club_organizer(club_id));

create policy "trips_update_organizers"
  on public.trips for update
  to authenticated
  using (public.is_club_organizer(club_id))
  with check (public.is_club_organizer(club_id));

create policy "trips_delete_organizers"
  on public.trips for delete
  to authenticated
  using (public.is_club_organizer(club_id));
