-- Logiktest für Benachrichtigungen (Etappe 7): Trigger, Postausgang, Versand-RPCs, Push-Abos.
-- Läuft komplett in einer Transaktion und wird am Ende zurückgerollt, hinterlässt also keine Daten.
-- Ausführen: pnpm exec supabase db query --remote --yes -f supabase/checks/notifications.sql
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
  trip uuid;
  round uuid;
  cat uuid;
  req_u3 uuid;
  req_u1 uuid;
  reg_u1 uuid;
  n integer;
  rec record;
  failed boolean;
  label text;
begin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, 'authenticated', 'authenticated', 'test-' || id || '@example.invalid', '{}', '{}', now(), now()
  from unnest(array[orga, u1, u2, u3]) as id;

  insert into public.clubs (id, name) values (club, 'Testclub');
  insert into public.club_members (club_id, user_id, role) values
    (club, orga, 'organizer'), (club, u1, 'member'), (club, u2, 'member'), (club, u3, 'member');
  insert into public.away_games (id, club_id, openligadb_match_id, league_shortcut, season, matchday, opponent_name)
  values (game, club, 999999, 'bl1', 2026, 7, 'Testgegner');

  -- 0) Datumsformat
  label := private.format_berlin_datetime('2026-11-21 14:30:00+00');
  if label <> 'Sa., 21.11., 15:30 Uhr' then raise exception '0: %', label; end if;

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);

  -- 1) Neue Fahrt -> alle Mitglieder außer Organisator
  insert into public.trips (club_id, away_game_id, transport, capacity) values (club, game, 'bus', 1) returning id into trip;
  reset role;
  select count(*) into n from public.notifications where kind = 'trip_created';
  if n <> 3 then raise exception '1a: % statt 3', n; end if;
  if exists (select 1 from public.notifications where user_id = orga) then raise exception '1b: Organisator benachrichtigt'; end if;

  -- 2) Neue Ticketabfrage -> alle Mitglieder außer Organisator
  set local role authenticated;
  insert into public.ticket_rounds (club_id, away_game_id, request_deadline) values (club, game, now() + interval '3 days') returning id into round;
  insert into public.ticket_categories (round_id, club_id, name, price_cents, quota) values (round, club, 'Stehplatz', 1800, 5) returning id into cat;
  reset role;
  select count(*) into n from public.notifications where kind = 'ticket_round_opened' and body like '%bis %Uhr%';
  if n <> 3 then raise exception '2: % statt 3', n; end if;

  -- 3) Nachrücken
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  perform public.register_for_trip(trip);
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform public.register_for_trip(trip);
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select id into reg_u1 from public.trip_registrations where trip_id = trip and user_id = u1;
  perform public.cancel_trip_registration(reg_u1);
  reset role;
  select count(*) into n from public.notifications where kind = 'waitlist_promoted' and user_id = u2 and title = 'Du bist nachgerückt';
  if n <> 1 then raise exception '3: % statt 1', n; end if;

  -- 4) Ticket zugeteilt, PDF da, Abholung festgelegt
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  req_u3 := public.request_ticket(cat, 'Inhaber Drei', null);
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  perform public.set_ticket_request_status(req_u3, 'allocated');
  insert into storage.objects (bucket_id, name, owner_id) values ('ticket-files', club || '/' || req_u3 || '.pdf', orga);
  perform public.attach_ticket_file(req_u3);
  perform public.set_ticket_delivery(array[req_u3], 'pickup', 'Am Bus', '2026-11-21 08:00:00+00');
  reset role;
  select count(*) into n from public.notifications where user_id = u3 and kind = 'ticket_allocated';
  if n <> 1 then raise exception '4a: zugeteilt %', n; end if;
  select count(*) into n from public.notifications where user_id = u3 and kind = 'ticket_delivery' and title = 'Dein Ticket ist da';
  if n <> 1 then raise exception '4b: PDF %', n; end if;
  select count(*) into n from public.notifications where user_id = u3 and kind = 'ticket_delivery' and body like '%Abholung Am Bus, Sa., 21.11., 09:00 Uhr%';
  if n <> 1 then raise exception '4c: Abholung %', n; end if;

  -- 5) Abgelehnt
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  req_u1 := public.request_ticket(cat, 'Inhaber Eins', null);
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  perform public.set_ticket_request_status(req_u1, 'rejected');
  reset role;
  select count(*) into n from public.notifications where user_id = u1 and kind = 'ticket_rejected';
  if n <> 1 then raise exception '5: abgelehnt %', n; end if;

  -- 6) Anstoßzeit: fest, geändert, Vergangenheit; nur aktive Anmeldungen/Anfragen (u2 Fahrt, u3 Ticket)
  update public.away_games set kickoff_at = now() + interval '7 days' where id = game;
  select count(*) into n from public.notifications where kind = 'kickoff_scheduled';
  if n <> 2 then raise exception '6a: fest % statt 2', n; end if;
  if exists (select 1 from public.notifications where kind = 'kickoff_scheduled' and user_id = u1) then
    raise exception '6b: Abgesagtes Mitglied benachrichtigt';
  end if;
  update public.away_games set kickoff_at = now() + interval '8 days' where id = game;
  select count(*) into n from public.notifications where kind = 'kickoff_changed';
  if n <> 2 then raise exception '6c: geändert % statt 2', n; end if;
  update public.away_games set kickoff_at = now() - interval '40 days' where id = game;
  select count(*) into n from public.notifications where kind in ('kickoff_scheduled', 'kickoff_changed');
  if n <> 4 then raise exception '6d: Vergangene Anstoßzeit gemeldet'; end if;

  -- 7) RLS: Mitglieder sehen nur eigene Benachrichtigungen und können keine anlegen
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.notifications where user_id <> u1;
  if n <> 0 then raise exception '7a: Fremde Benachrichtigungen sichtbar'; end if;
  failed := false;
  begin
    insert into public.notifications (user_id, kind, title, body, url) values (u2, 'trip_created', 'x', 'y', '/');
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '7b: Mitglied konnte Benachrichtigung anlegen'; end if;

  -- 8) Versand-RPCs nur für service_role
  failed := false;
  begin
    perform public.claim_notifications(10);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '8: Mitglied konnte Postausgang abholen'; end if;

  -- 9) Push-Abo: Gerät wechselt den Besitzer
  perform public.save_push_subscription('https://push.example/abc', 'key', 'auth', 'Test');
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform public.save_push_subscription('https://push.example/abc', 'key2', 'auth2', 'Test');
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.push_subscriptions;
  if n <> 0 then raise exception '9: Altes Abo noch sichtbar'; end if;
  reset role;
  select count(*) into n from public.push_subscriptions where endpoint = 'https://push.example/abc' and user_id = u2;
  if n <> 1 then raise exception '9b: Abo nicht übertragen'; end if;

  -- 10) Abholen und Abschließen als service_role
  set local role service_role;
  select count(*) into n from public.claim_notifications(100);
  if n < 10 then raise exception '10a: nur % abgeholt', n; end if;
  select count(*) into n from public.claim_notifications(100);
  if n <> 0 then raise exception '10b: doppelt abgeholt (%)', n; end if;
  perform public.complete_notifications(array(select id from public.notifications where status = 'sending'), true, null);
  select count(*) into n from public.notifications where status <> 'sent';
  if n <> 0 then raise exception '10c: % nicht als gesendet markiert', n; end if;

  select * into rec from public.notification_recipients(array[u1]);
  if rec.email <> 'test-' || u1 || '@example.invalid' or rec.email_notifications is not true then
    raise exception '10d: %', rec;
  end if;
  reset role;
end;
$$;

select 'Alle Prüfungen bestanden' as result;

rollback;
