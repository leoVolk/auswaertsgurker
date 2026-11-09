-- Etappe 1: Profile, Fanclubs, Mitgliedschaften und Einladungslinks

create extension if not exists pgcrypto with schema extensions;

create type public.club_role as enum ('organizer', 'member');

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) between 2 and 40),
  created_at timestamptz not null default now()
);

comment on column public.profiles.display_name is 'Anzeigename im Fanclub; null bis zum Onboarding';

create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 80),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.club_members (
  club_id uuid not null references public.clubs (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.club_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

create index club_members_user_id_idx on public.club_members (user_id);

create table public.club_invites (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs (id) on delete cascade,
  -- 96 Bit Zufall, URL-sicher (16 Zeichen)
  token text not null unique
    default translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/', '-_'),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

-- Pro Fanclub ist höchstens ein Einladungslink aktiv
create unique index club_invites_one_active_per_club
  on public.club_invites (club_id)
  where revoked_at is null;

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen für Policies (security definer verhindert RLS-Rekursion)
-- ---------------------------------------------------------------------------

create function public.is_club_member(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.club_members
    where club_id = p_club_id
      and user_id = auth.uid()
  );
$$;

create function public.is_club_organizer(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.club_members
    where club_id = p_club_id
      and user_id = auth.uid()
      and role = 'organizer'
  );
$$;

create function public.shares_club_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.club_members mine
    join public.club_members theirs on theirs.club_id = mine.club_id
    where mine.user_id = auth.uid()
      and theirs.user_id = p_user_id
  );
$$;

-- ---------------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------------

-- Profil bei der Registrierung anlegen
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Bereits vorhandene Accounts nachziehen
insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;

-- Ein Fanclub behält immer mindestens einen Organisator
create function public.ensure_club_keeps_organizer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Admin-Vorgänge ohne angemeldeten User (z. B. Account im Dashboard löschen)
  -- und Kaskaden beim Löschen eines Fanclubs nicht blockieren
  if auth.uid() is null
    or not exists (select 1 from public.clubs where id = old.club_id) then
    return coalesce(new, old);
  end if;

  if old.role = 'organizer'
    and (tg_op = 'DELETE' or new.role <> 'organizer')
    and not exists (
      select 1
      from public.club_members
      where club_id = old.club_id
        and role = 'organizer'
        and user_id <> old.user_id
    ) then
    raise exception 'Ein Fanclub braucht mindestens einen Organisator.';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger club_members_keep_organizer
  before update of role or delete on public.club_members
  for each row execute function public.ensure_club_keeps_organizer();

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Fanclub anlegen: Ersteller wird Organisator, Einladungslink entsteht direkt
create function public.create_club(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_club uuid;
begin
  if v_user is null then
    raise exception 'Du bist nicht angemeldet.';
  end if;

  insert into public.clubs (name, created_by)
  values (btrim(p_name), v_user)
  returning id into v_club;

  insert into public.club_members (club_id, user_id, role)
  values (v_club, v_user, 'organizer');

  insert into public.club_invites (club_id, created_by)
  values (v_club, v_user);

  return v_club;
end;
$$;

-- Vorschau für die Einladungsseite, auch ohne Login abrufbar
create function public.get_invite(p_token text)
returns table (club_id uuid, club_name text, is_member boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.name, public.is_club_member(c.id)
  from public.club_invites i
  join public.clubs c on c.id = i.club_id
  where i.token = p_token
    and i.revoked_at is null;
$$;

-- Per Einladungslink als Mitglied beitreten (mehrfaches Beitreten schadet nicht)
create function public.join_club(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_club uuid;
begin
  if v_user is null then
    raise exception 'Du bist nicht angemeldet.';
  end if;

  select club_id into v_club
  from public.club_invites
  where token = p_token
    and revoked_at is null;

  if v_club is null then
    raise exception 'Dieser Einladungslink ist ungültig oder wurde ersetzt.';
  end if;

  insert into public.club_members (club_id, user_id, role)
  values (v_club, v_user, 'member')
  on conflict (club_id, user_id) do nothing;

  return v_club;
end;
$$;

-- Neuen Einladungslink erzeugen, der bisherige wird ungültig
create function public.regenerate_invite(p_club_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  if not public.is_club_organizer(p_club_id) then
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
$$;

-- ---------------------------------------------------------------------------
-- Rechte auf Funktionen
-- ---------------------------------------------------------------------------

revoke execute on function
  public.is_club_member(uuid),
  public.is_club_organizer(uuid),
  public.shares_club_with(uuid),
  public.handle_new_user(),
  public.ensure_club_keeps_organizer(),
  public.create_club(text),
  public.get_invite(text),
  public.join_club(text),
  public.regenerate_invite(uuid)
from public, anon, authenticated;

grant execute on function
  public.is_club_member(uuid),
  public.is_club_organizer(uuid),
  public.shares_club_with(uuid),
  public.create_club(text),
  public.join_club(text),
  public.regenerate_invite(uuid)
to authenticated;

grant execute on function public.get_invite(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_invites enable row level security;

-- profiles: eigenes Profil plus Profile aus gemeinsamen Fanclubs lesen, nur eigenes ändern
create policy "profiles_select_own_or_shared_club"
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()) or public.shares_club_with(id));

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- clubs: Mitglieder lesen, Organisatoren ändern; Anlegen nur über create_club
create policy "clubs_select_members"
  on public.clubs for select
  to authenticated
  using (public.is_club_member(id));

create policy "clubs_update_organizers"
  on public.clubs for update
  to authenticated
  using (public.is_club_organizer(id))
  with check (public.is_club_organizer(id));

-- club_members: Mitglieder lesen, Organisatoren ändern Rollen und entfernen;
-- Beitreten nur über create_club / join_club
create policy "club_members_select_members"
  on public.club_members for select
  to authenticated
  using (public.is_club_member(club_id));

create policy "club_members_update_organizers"
  on public.club_members for update
  to authenticated
  using (public.is_club_organizer(club_id))
  with check (public.is_club_organizer(club_id));

create policy "club_members_delete_organizers"
  on public.club_members for delete
  to authenticated
  using (public.is_club_organizer(club_id));

-- club_invites: nur Organisatoren lesen; Anlegen/Erneuern nur über RPCs
create policy "club_invites_select_organizers"
  on public.club_invites for select
  to authenticated
  using (public.is_club_organizer(club_id));

-- ---------------------------------------------------------------------------
-- Spaltenrechte: nur fachlich änderbare Spalten dürfen per UPDATE geändert werden
-- ---------------------------------------------------------------------------

revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (display_name) on public.profiles to authenticated;

revoke insert, update, delete on public.clubs from anon, authenticated;
grant update (name) on public.clubs to authenticated;

revoke insert, update, delete on public.club_members from anon, authenticated;
grant update (role) on public.club_members to authenticated;
grant delete on public.club_members to authenticated;

revoke insert, update, delete on public.club_invites from anon, authenticated;
