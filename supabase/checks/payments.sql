-- Logiktest für Zahlungen (Etappe 5).
-- Läuft komplett in einer Transaktion und wird am Ende zurückgerollt, hinterlässt also keine Daten.
-- Ausführen: pnpm exec supabase db query --remote --yes -f supabase/checks/payments.sql
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
  reg1 uuid := '22222222-0000-4000-8000-000000000001';
  reg2 uuid := '22222222-0000-4000-8000-000000000002';
  t1 uuid := '11111111-0000-4000-8000-000000000001';
  t2 uuid := '11111111-0000-4000-8000-000000000002';
  t3 uuid := '11111111-0000-4000-8000-000000000003';
  path1 text;
  n integer;
  rec record;
  failed boolean;
begin
  -- Aufbau als Admin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, 'authenticated', 'authenticated', 'test-' || id || '@example.invalid', '{}', '{}', now(), now()
  from unnest(array[orga, u1, u2]) as id;

  insert into public.clubs (id, name, paypal_me) values (club, 'Testclub', 'TestFanclub');
  insert into public.club_members (club_id, user_id, role) values
    (club, orga, 'organizer'), (club, u1, 'member'), (club, u2, 'member');
  insert into public.away_games (id, club_id, openligadb_match_id, league_shortcut, season, matchday, opponent_name)
  values (game, club, 999999, 'bl1', 2026, 1, 'Testgegner');
  insert into public.trips (id, club_id, away_game_id, transport, price_cents) values (trip, club, game, 'bus', 2500);
  insert into public.trip_registrations (id, trip_id, club_id, user_id, status) values
    (reg1, trip, club, u1, 'requested'), (reg2, trip, club, u2, 'waitlist');
  insert into public.ticket_rounds (id, club_id, away_game_id) values (round, club, game);
  insert into public.ticket_categories (id, round_id, club_id, name, price_cents, quota)
  values (cat, round, club, 'Stehplatz', 1800, 10);
  insert into public.ticket_requests (id, club_id, round_id, category_id, requested_by, holder_name, status) values
    (t1, club, round, cat, u1, 'Eins A', 'allocated'),
    (t2, club, round, cat, u1, 'Eins B', 'allocated'),
    (t3, club, round, cat, u2, 'Zwei', 'requested');

  set local role authenticated;

  -- 1) u1 meldet Fahrt und beide Tickets
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  n := public.report_payment(array[reg1], array[t1, t2]);
  if n <> 3 then raise exception '1a: % statt 3 gemeldet', n; end if;
  select payment_status, payment_amount_cents into rec from public.trip_registrations where id = reg1;
  if rec.payment_status <> 'reported' or rec.payment_amount_cents <> 2500 then raise exception '1b: %', rec; end if;
  select payment_status, payment_amount_cents into rec from public.ticket_requests where id = t2;
  if rec.payment_status <> 'reported' or rec.payment_amount_cents <> 1800 then raise exception '1c: %', rec; end if;

  -- 2) Erneutes Melden geht nicht
  failed := false;
  begin
    perform public.report_payment(array[reg1], array[t1]);
  exception when others then failed := true;
  end;
  if not failed then raise exception '2: Doppelt gemeldet'; end if;

  -- 3) u2 kann weder Warteliste noch fremde oder nicht zugeteilte Posten melden
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.report_payment(array[reg2, reg1], array[t3, t1]);
  exception when others then failed := true;
  end;
  if not failed then raise exception '3: Unzulässige Posten gemeldet'; end if;

  -- 4) Mitglied darf keinen Status setzen, auch nicht direkt
  failed := false;
  begin
    perform public.set_payment_status('confirmed', array[reg2], '{}');
  exception when others then failed := true;
  end;
  if not failed then raise exception '4a: Mitglied konnte Zahlung bestätigen'; end if;
  failed := false;
  begin
    update public.ticket_requests set payment_status = 'confirmed' where id = t3;
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '4b: Direktes UPDATE möglich'; end if;

  -- 5) Organisator darf nicht "gemeldet" setzen und nichts Unbestätigtes erstatten
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.set_payment_status('reported', array[reg2], '{}');
  exception when others then failed := true;
  end;
  if not failed then raise exception '5a: Organisator konnte "gemeldet" setzen'; end if;
  failed := false;
  begin
    perform public.set_payment_status('refunded', array[reg1], '{}');
  exception when others then failed := true;
  end;
  if not failed then raise exception '5b: Gemeldete Zahlung erstattet'; end if;

  -- 6) Bestätigen, dann Fahrt erstatten
  n := public.set_payment_status('confirmed', array[reg1], array[t1, t2]);
  if n <> 3 then raise exception '6a: % statt 3 bestätigt', n; end if;
  perform public.set_payment_status('refunded', array[reg1], '{}');
  select payment_status into rec from public.trip_registrations where id = reg1;
  if rec.payment_status <> 'refunded' then raise exception '6b: %', rec; end if;

  -- 7) Zurück auf offen löscht den Betrag; Barzahlung direkt bestätigen setzt ihn
  perform public.set_payment_status('open', '{}', array[t2]);
  select payment_status, payment_amount_cents into rec from public.ticket_requests where id = t2;
  if rec.payment_status <> 'open' or rec.payment_amount_cents is not null then raise exception '7a: %', rec; end if;
  perform public.set_payment_status('confirmed', '{}', array[t3]);
  select payment_amount_cents into rec from public.ticket_requests where id = t3;
  if rec.payment_amount_cents <> 1800 then raise exception '7b: %', rec; end if;

  -- 8) Eigener Zahlungsstatus in get_trip_stats
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select * into rec from public.get_trip_stats(club) where trip_id = trip;
  if rec.my_payment_status <> 'refunded' then raise exception '8: %', rec; end if;

  -- 9) PDF erst nach bestätigter Zahlung
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  path1 := club || '/' || t2 || '.pdf';
  insert into storage.objects (bucket_id, name, owner_id) values ('ticket-files', path1, orga);
  perform public.attach_ticket_file(t2);
  update public.ticket_rounds set download_requires_payment = true where id = round;

  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from storage.objects where name = path1;
  if n <> 0 then raise exception '9a: PDF trotz offener Zahlung sichtbar'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  perform public.set_payment_status('confirmed', '{}', array[t2]);

  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from storage.objects where name = path1;
  if n <> 1 then raise exception '9b: PDF nach Bestätigung nicht sichtbar'; end if;

  reset role;
end;
$$;

select 'Alle Prüfungen bestanden' as result;

rollback;
