-- Logiktest für „Fanclub löschen“ und „Fanclub verlassen“.
-- Läuft komplett in einer Transaktion und wird am Ende zurückgerollt, hinterlässt also keine Daten.
-- Ausführen: pnpm exec supabase db query --remote --yes -f supabase/checks/club_deletion.sql
-- Erwartete Ausgabe: "Alle Prüfungen bestanden"; sonst bricht der Test mit der Nummer der Prüfung ab.

begin;

do $$
declare
  orga uuid := 'aaaaaaaa-0000-4000-8000-000000000000';
  u1 uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  u2 uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
  club uuid := 'bbbbbbbb-0000-4000-8000-000000000000';
  game uuid := 'cccccccc-0000-4000-8000-000000000000';
  trip uuid := 'dddddddd-0000-4000-8000-000000000000';
  round uuid := 'eeeeeeee-0000-4000-8000-000000000000';
  cat uuid := 'ffffffff-0000-4000-8000-000000000000';
  open_req uuid := '11111111-0000-4000-8000-000000000001';
  alloc_req uuid := '11111111-0000-4000-8000-000000000002';
  n integer;
  rec record;
  s text;
  failed boolean;
begin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, 'authenticated', 'authenticated', 'test-' || id || '@example.invalid', '{}', '{}', now(), now()
  from unnest(array[orga, u1, u2]) as id;

  insert into public.clubs (id, name) values (club, 'Testclub');
  insert into public.club_members (club_id, user_id, role) values
    (club, orga, 'organizer'), (club, u1, 'member'), (club, u2, 'member');
  insert into public.club_invites (club_id) values (club);
  insert into public.away_games (id, club_id, openligadb_match_id, league_shortcut, season, matchday, opponent_name, kickoff_at)
  values (game, club, 999999, 'bl1', 2026, 1, 'Testgegner', now() + interval '10 days');
  insert into public.trips (id, club_id, away_game_id, transport, capacity, price_cents) values (trip, club, game, 'bus', 1, 2000);
  insert into public.trip_registrations (trip_id, club_id, user_id, status, payment_status) values
    (trip, club, u1, 'confirmed', 'confirmed'),
    (trip, club, u2, 'waitlist', 'open');
  insert into public.ticket_rounds (id, club_id, away_game_id) values (round, club, game);
  insert into public.ticket_categories (id, round_id, club_id, name, price_cents) values (cat, round, club, 'Stehplatz', 1800);
  insert into public.ticket_requests (id, club_id, round_id, category_id, requested_by, holder_name, status, payment_status, ticket_file_path) values
    (open_req, club, round, cat, u1, 'Offen', 'requested', 'open', null),
    (alloc_req, club, round, cat, u1, 'Zugeteilt', 'allocated', 'confirmed', club || '/x.pdf');
  insert into public.notifications (user_id, club_id, kind, title, body, url)
  values (u2, club, 'trip_created', 'Test', 'Test', '/');

  set local role authenticated;

  -- 1) Mitglied sieht keine Zusammenfassung und kann den Fanclub nicht löschen
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.club_deletion_summary(club);
  if n <> 0 then raise exception '1a: Mitglied sieht Zusammenfassung'; end if;
  delete from public.clubs where id = club;
  reset role;
  select count(*) into n from public.clubs where id = club;
  if n <> 1 then raise exception '1b: Mitglied konnte Fanclub löschen'; end if;
  set local role authenticated;

  -- 2) Zusammenfassung für Organisatoren
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  select * into rec from public.club_deletion_summary(club);
  if rec.members <> 3 or rec.trips <> 1 or rec.ticket_rounds <> 1 or rec.open_payments <> 2 or rec.ticket_files <> 1 then
    raise exception '2: %', rec;
  end if;

  -- 3) u1 verlässt den Fanclub: Fahrt storniert (u2 rückt nach), offene Ticketanfrage storniert,
  --    zugeteiltes Ticket bleibt
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  delete from public.club_members where club_id = club and user_id = u1;
  reset role;
  select count(*) into n from public.club_members where club_id = club and user_id = u1;
  if n <> 0 then raise exception '3a: Austritt fehlgeschlagen'; end if;
  select status::text into s from public.trip_registrations where trip_id = trip and user_id = u1;
  if s <> 'cancelled' then raise exception '3b: Fahrt nicht storniert (%)', s; end if;
  select status::text into s from public.trip_registrations where trip_id = trip and user_id = u2;
  if s <> 'requested' then raise exception '3c: u2 nicht nachgerückt (%)', s; end if;
  select status::text into s from public.ticket_requests where id = open_req;
  if s <> 'cancelled' then raise exception '3d: Offene Ticketanfrage nicht storniert (%)', s; end if;
  select status::text into s from public.ticket_requests where id = alloc_req;
  if s <> 'allocated' then raise exception '3e: Zugeteiltes Ticket verändert (%)', s; end if;
  set local role authenticated;

  -- 4) Mitglied kann andere nicht entfernen
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  delete from public.club_members where club_id = club and user_id = orga;
  reset role;
  select count(*) into n from public.club_members where club_id = club and user_id = orga;
  if n <> 1 then raise exception '4: Mitglied konnte Organisator entfernen'; end if;
  set local role authenticated;

  -- 5) Letzter Organisator kann nicht austreten
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    delete from public.club_members where club_id = club and user_id = orga;
  exception when others then failed := true;
  end;
  if not failed then raise exception '5: Letzter Organisator konnte austreten'; end if;

  -- 6) Organisator löscht den Fanclub: alles Abhängige ist weg
  delete from public.clubs where id = club;
  reset role;
  select
    (select count(*) from public.clubs where id = club)
    + (select count(*) from public.club_members where club_id = club)
    + (select count(*) from public.club_invites where club_id = club)
    + (select count(*) from public.away_games where club_id = club)
    + (select count(*) from public.trips where club_id = club)
    + (select count(*) from public.trip_registrations where club_id = club)
    + (select count(*) from public.ticket_rounds where club_id = club)
    + (select count(*) from public.ticket_categories where club_id = club)
    + (select count(*) from public.ticket_requests where club_id = club)
    + (select count(*) from public.notifications where club_id = club)
  into n;
  if n <> 0 then raise exception '6: % Zeilen übrig', n; end if;

  -- 7) Profile bleiben erhalten
  select count(*) into n from public.profiles where id in (orga, u1, u2);
  if n <> 3 then raise exception '7: Profile gelöscht'; end if;
end;
$$;

select 'Alle Prüfungen bestanden' as result;

rollback;
