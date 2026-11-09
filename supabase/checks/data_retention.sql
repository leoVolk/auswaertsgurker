-- Logiktest für die Löschfrist (Etappe 6).
-- Läuft komplett in einer Transaktion und wird am Ende zurückgerollt, hinterlässt also keine Daten.
-- Ausführen: pnpm exec supabase db query --remote --yes -f supabase/checks/data_retention.sql
-- Erwartete Ausgabe: "Alle Prüfungen bestanden"; sonst bricht der Test mit der Nummer der Prüfung ab.

begin;

do $$
declare
  orga uuid := 'aaaaaaaa-0000-4000-8000-000000000000';
  u1 uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  club uuid := 'bbbbbbbb-0000-4000-8000-000000000000';
  old_game uuid := 'cccccccc-0000-4000-8000-000000000001';
  new_game uuid := 'cccccccc-0000-4000-8000-000000000002';
  old_round uuid := 'eeeeeeee-0000-4000-8000-000000000001';
  new_round uuid := 'eeeeeeee-0000-4000-8000-000000000002';
  old_cat uuid := 'ffffffff-0000-4000-8000-000000000001';
  new_cat uuid := 'ffffffff-0000-4000-8000-000000000002';
  kickoff timestamptz := now() - interval '40 days';
  n integer;
  rec record;
  failed boolean;
begin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, 'authenticated', 'authenticated', 'test-' || id || '@example.invalid', '{}', '{}', now(), now()
  from unnest(array[orga, u1]) as id;

  insert into public.clubs (id, name) values (club, 'Testclub');
  insert into public.club_members (club_id, user_id, role) values (club, orga, 'organizer'), (club, u1, 'member');
  insert into public.away_games (id, club_id, openligadb_match_id, league_shortcut, season, matchday, opponent_name) values
    (old_game, club, 999998, 'bl1', 2026, 1, 'Alter Gegner'),
    (new_game, club, 999999, 'bl1', 2026, 2, 'Neuer Gegner');
  insert into public.ticket_rounds (id, club_id, away_game_id) values (old_round, club, old_game), (new_round, club, new_game);
  insert into public.ticket_categories (id, round_id, club_id, name, price_cents) values
    (old_cat, old_round, club, 'Stehplatz', 1800), (new_cat, new_round, club, 'Stehplatz', 1800);
  insert into public.ticket_requests (club_id, round_id, category_id, requested_by, holder_name, holder_membership_number, status, delivery_method, ticket_file_path) values
    (club, old_round, old_cat, u1, 'Alt Eins', 'M-1', 'allocated', 'digital', club || '/x1.pdf'),
    (club, old_round, old_cat, u1, 'Alt Zwei', 'M-2', 'cancelled', null, null),
    (club, old_round, old_cat, u1, 'Alt Drei', null, 'requested', null, null),
    (club, new_round, new_cat, u1, 'Neu', 'M-3', 'allocated', 'digital', club || '/x2.pdf');

  -- 1) Organisatoren und Mitglieder dürfen die Funktion nicht aufrufen
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.purge_away_game_ticket_data(old_game, kickoff);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '1: Organisator konnte löschen'; end if;
  reset role;

  -- 2) Mit service_role: altes Spiel wird geleert und markiert
  set local role service_role;
  n := public.purge_away_game_ticket_data(old_game, kickoff);
  if n <> 2 then raise exception '2a: % statt 2 Anfragen geleert', n; end if;

  select count(*) into n from public.ticket_requests
  where round_id = old_round and (holder_membership_number is not null or ticket_file_path is not null);
  if n <> 0 then raise exception '2b: % Anfragen haben noch Daten', n; end if;

  select personal_data_purged_at, kickoff_at into rec from public.away_games where id = old_game;
  if rec.personal_data_purged_at is null or rec.kickoff_at <> kickoff then raise exception '2c: %', rec; end if;

  -- 3) Inhabernamen und Status bleiben erhalten
  select count(*) into n from public.ticket_requests where round_id = old_round and holder_name like 'Alt %';
  if n <> 3 then raise exception '3: Inhabernamen verändert'; end if;

  -- 4) Anderes Spiel bleibt unberührt
  select holder_membership_number, ticket_file_path into rec from public.ticket_requests where round_id = new_round;
  if rec.holder_membership_number <> 'M-3' or rec.ticket_file_path is null then raise exception '4: %', rec; end if;
  select personal_data_purged_at into rec from public.away_games where id = new_game;
  if rec.personal_data_purged_at is not null then raise exception '4b: Neues Spiel markiert'; end if;

  -- 5) Zweiter Aufruf ändert nichts mehr
  n := public.purge_away_game_ticket_data(old_game, null);
  if n <> 0 then raise exception '5: Zweiter Aufruf hat % Anfragen geändert', n; end if;
  select kickoff_at into rec from public.away_games where id = old_game;
  if rec.kickoff_at <> kickoff then raise exception '5b: Anstoß überschrieben'; end if;

  reset role;
end;
$$;

select 'Alle Prüfungen bestanden' as result;

rollback;
