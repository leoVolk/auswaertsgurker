-- Logiktest für Anmeldung, Warteliste und Nachrücken (Etappe 3).
-- Läuft komplett in einer Transaktion und wird am Ende zurückgerollt, hinterlässt also keine Daten.
-- Ausführen: pnpm exec supabase db query --remote --yes -f supabase/checks/trip_registrations.sql
-- Erwartete Ausgabe: "Alle Prüfungen bestanden"; sonst bricht der Test mit der Nummer der Prüfung ab.

begin;

do $$
declare
  orga uuid := 'aaaaaaaa-0000-4000-8000-000000000000';
  u1 uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  u2 uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
  u3 uuid := 'aaaaaaaa-0000-4000-8000-000000000003';
  club uuid := 'bbbbbbbb-0000-4000-8000-000000000000';
  game uuid := 'cccccccc-0000-4000-8000-000000000000';
  trip uuid := 'dddddddd-0000-4000-8000-000000000000';
  s public.registration_status;
  n integer;
  rec record;
  failed boolean;
begin
  -- Aufbau als Admin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, 'authenticated', 'authenticated', 'test-' || id || '@example.invalid', '{}', '{}', now(), now()
  from unnest(array[orga, u1, u2, u3]) as id;

  insert into public.clubs (id, name) values (club, 'Testclub');
  insert into public.club_members (club_id, user_id, role) values
    (club, orga, 'organizer'), (club, u1, 'member'), (club, u2, 'member'), (club, u3, 'member');
  insert into public.away_games (id, club_id, openligadb_match_id, league_shortcut, season, matchday, opponent_name)
  values (game, club, 999999, 'bl1', 2026, 1, 'Testgegner');
  insert into public.trips (id, club_id, away_game_id, transport, capacity)
  values (trip, club, game, 'bus', 2);

  -- 1) u1 und u2 melden sich an -> requested; u3 -> waitlist
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  s := public.register_for_trip(trip);
  if s <> 'requested' then raise exception '1a: erwartet requested, war %', s; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  s := public.register_for_trip(trip);
  if s <> 'requested' then raise exception '1b: erwartet requested, war %', s; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  s := public.register_for_trip(trip);
  if s <> 'waitlist' then raise exception '1c: erwartet waitlist, war %', s; end if;

  -- 2) Doppelte Anmeldung ändert nichts
  s := public.register_for_trip(trip);
  if s <> 'waitlist' then raise exception '2: erwartet waitlist, war %', s; end if;

  -- 3) Statistik aus Sicht von u3
  select * into rec from public.get_trip_stats(club) where trip_id = trip;
  if rec.taken_seats <> 2 or rec.waitlist_count <> 1 or rec.my_status <> 'waitlist' or rec.my_waitlist_position <> 1 then
    raise exception '3: Statistik falsch: %', rec;
  end if;

  -- 4) RLS: u3 sieht nur die eigene Anmeldung
  select count(*) into n from public.trip_registrations;
  if n <> 1 then raise exception '4: u3 sieht % Anmeldungen statt 1', n; end if;

  -- 5) Mitglied darf nicht bestätigen
  failed := false;
  begin
    perform public.confirm_all_trip_registrations(trip);
  exception when others then failed := true;
  end;
  if not failed then raise exception '5: Mitglied konnte bestätigen'; end if;

  -- 6) Direktes Schreiben ist verboten
  failed := false;
  begin
    update public.trip_registrations set status = 'confirmed';
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '6: Direktes UPDATE war erlaubt'; end if;

  -- 7) u1 sagt ab -> u3 rückt nach
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select id into rec from public.trip_registrations where user_id = u1;
  perform public.cancel_trip_registration(rec.id);

  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  select status into s from public.trip_registrations where trip_id = trip and user_id = u3;
  if s <> 'requested' then raise exception '7: u3 ist nicht nachgerückt (%)', s; end if;

  -- 8) Organisator sieht alle und bestätigt alle offenen Anfragen
  select count(*) into n from public.trip_registrations where trip_id = trip;
  if n <> 3 then raise exception '8a: Organisator sieht % statt 3', n; end if;
  n := public.confirm_all_trip_registrations(trip);
  if n <> 2 then raise exception '8b: % statt 2 bestätigt', n; end if;

  -- 9) u1 meldet sich neu an -> waitlist (voll)
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  s := public.register_for_trip(trip);
  if s <> 'waitlist' then raise exception '9: erwartet waitlist, war %', s; end if;

  -- 10) Organisator erhöht Plätze -> u1 rückt nach
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  update public.trips set capacity = 3 where id = trip;
  select status into s from public.trip_registrations where trip_id = trip and user_id = u1;
  if s <> 'requested' then raise exception '10: u1 ist nach Kapazitätserhöhung nicht nachgerückt (%)', s; end if;

  -- 11) Platzzahl wieder 2, u3 auf Warteliste setzen ist nicht vorgesehen; stattdessen:
  --     u2 wird aus dem Fanclub entfernt -> Anmeldung storniert
  delete from public.club_members where club_id = club and user_id = u2;
  select status into s from public.trip_registrations where trip_id = trip and user_id = u2;
  if s <> 'cancelled' then raise exception '11: Anmeldung von u2 nicht storniert (%)', s; end if;

  -- 12) Ehemaliges Mitglied kann sich nicht mehr anmelden
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.register_for_trip(trip);
  exception when others then failed := true;
  end;
  if not failed then raise exception '12: Ex-Mitglied konnte sich anmelden'; end if;

  -- 13) Anmeldeschluss vorbei -> keine Anmeldung
  reset role;
  update public.trips set registration_deadline = now() - interval '1 minute' where id = trip;
  delete from public.trip_registrations where user_id = u3;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.register_for_trip(trip);
  exception when others then failed := true;
  end;
  if not failed then raise exception '13: Anmeldung nach Anmeldeschluss möglich'; end if;

  reset role;
  raise notice 'Alle Prüfungen bestanden';
end;
$$;

select 'Alle Prüfungen bestanden' as result;

rollback;
