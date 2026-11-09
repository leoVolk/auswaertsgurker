-- Logiktest für die Ticket-Hinterlegung (Storage-Policies und RPCs).
-- Läuft komplett in einer Transaktion und wird am Ende zurückgerollt, hinterlässt also keine Daten.
-- Uploads werden als Zeilen in storage.objects simuliert; dort greifen dieselben Policies wie über die API.
-- Ausführen: pnpm exec supabase db query --remote --yes -f supabase/checks/ticket_delivery.sql
-- Erwartete Ausgabe: "Alle Prüfungen bestanden"; sonst bricht der Test mit der Nummer der Prüfung ab.

begin;

do $$
declare
  orga uuid := 'aaaaaaaa-0000-4000-8000-000000000000';
  u1 uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  u2 uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
  club uuid := 'bbbbbbbb-0000-4000-8000-000000000000';
  game uuid := 'cccccccc-0000-4000-8000-000000000000';
  round uuid := 'eeeeeeee-0000-4000-8000-000000000000';
  cat uuid := 'ffffffff-0000-4000-8000-000000000000';
  r1 uuid := '11111111-0000-4000-8000-000000000001';
  r2 uuid := '11111111-0000-4000-8000-000000000002';
  path1 text;
  path2 text;
  result text;
  n integer;
  rec record;
  failed boolean;
begin
  -- Aufbau als Admin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, 'authenticated', 'authenticated', 'test-' || id || '@example.invalid', '{}', '{}', now(), now()
  from unnest(array[orga, u1, u2]) as id;

  insert into public.clubs (id, name) values (club, 'Testclub');
  insert into public.club_members (club_id, user_id, role) values
    (club, orga, 'organizer'), (club, u1, 'member'), (club, u2, 'member');
  insert into public.away_games (id, club_id, openligadb_match_id, league_shortcut, season, matchday, opponent_name)
  values (game, club, 999999, 'bl1', 2026, 1, 'Testgegner');
  insert into public.ticket_rounds (id, club_id, away_game_id) values (round, club, game);
  insert into public.ticket_categories (id, round_id, club_id, name, price_cents, quota)
  values (cat, round, club, 'Stehplatz', 1800, 10);
  insert into public.ticket_requests (id, club_id, round_id, category_id, requested_by, holder_name, status)
  values (r1, club, round, cat, u1, 'Inhaber Eins', 'allocated'),
         (r2, club, round, cat, u2, 'Inhaber Zwei', 'requested');

  path1 := club || '/' || r1 || '.pdf';
  path2 := club || '/' || r2 || '.pdf';

  set local role authenticated;

  -- 1) Organisator lädt für ein zugeteiltes Ticket hoch, für ein nicht zugeteiltes nicht
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  insert into storage.objects (bucket_id, name, owner_id) values ('ticket-files', path1, orga);
  failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner_id) values ('ticket-files', path2, orga);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '1: Upload für nicht zugeteiltes Ticket möglich'; end if;

  -- 2) Mitglied darf nicht hochladen
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner_id) values ('ticket-files', path1 || '.x', u1);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '2: Mitglied konnte hochladen'; end if;

  -- 3) Vor dem Anhängen sieht die anfragende Person die Datei noch nicht
  select count(*) into n from storage.objects where name = path1;
  if n <> 0 then raise exception '3: Datei vor dem Anhängen sichtbar'; end if;

  -- 4) Organisator hängt die Datei an
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  result := public.attach_ticket_file(r1);
  if result <> path1 then raise exception '4a: falscher Pfad %', result; end if;
  select delivery_method, ticket_file_path into rec from public.ticket_requests where id = r1;
  if rec.delivery_method <> 'digital' or rec.ticket_file_path <> path1 then raise exception '4b: %', rec; end if;

  -- 5) Anfragende Person sieht die Datei, andere Mitglieder nicht
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from storage.objects where name = path1;
  if n <> 1 then raise exception '5a: Inhaber sieht die Datei nicht'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  select count(*) into n from storage.objects where name = path1;
  if n <> 0 then raise exception '5b: Fremdes Mitglied sieht die Datei'; end if;

  -- 6) Mitglied darf keine Hinterlegung festlegen
  failed := false;
  begin
    perform public.set_ticket_delivery(array[r1], 'box_office', null, null);
  exception when others then failed := true;
  end;
  if not failed then raise exception '6: Mitglied konnte Hinterlegung festlegen'; end if;

  -- 7) Abholung ohne Ort und Hinterlegung für nicht zugeteilte Tickets werden abgewiesen
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.set_ticket_delivery(array[r1], 'pickup', '  ', null);
  exception when others then failed := true;
  end;
  if not failed then raise exception '7a: Abholung ohne Ort möglich'; end if;
  failed := false;
  begin
    perform public.set_ticket_delivery(array[r2], 'box_office', null, null);
  exception when others then failed := true;
  end;
  if not failed then raise exception '7b: Hinterlegung für nicht zugeteiltes Ticket möglich'; end if;

  -- 8) Wechsel auf Abholung löst die Datei und liefert den Pfad zum Löschen
  select count(*) into n from public.set_ticket_delivery(array[r1], 'pickup', 'Am Bus', now()) as p where p = path1;
  if n <> 1 then raise exception '8: Pfad der gelösten Datei nicht zurückgegeben'; end if;
  select count(*) into n from public.set_ticket_delivery(array[r1], 'pickup', 'Am Bus', now());
  if n <> 0 then raise exception '8a: Zweiter Aufruf liefert noch Pfade'; end if;
  select delivery_method, pickup_location, ticket_file_path into rec from public.ticket_requests where id = r1;
  if rec.delivery_method <> 'pickup' or rec.pickup_location <> 'Am Bus' or rec.ticket_file_path is not null then
    raise exception '8b: %', rec;
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from storage.objects where name = path1;
  if n <> 0 then raise exception '8c: Gelöste Datei weiterhin für Inhaber sichtbar'; end if;

  -- 9) Wieder anhängen, dann stornieren -> Inhaber sieht die Datei nicht mehr
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  perform public.attach_ticket_file(r1);
  perform public.cancel_ticket_request(r1);
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select count(*) into n from storage.objects where name = path1;
  if n <> 0 then raise exception '9: Datei nach Stornierung für Inhaber sichtbar'; end if;

  -- 10) Ungültige Pfade führen nicht zu Fehlern
  if public.can_read_ticket_file('foo/bar.pdf') or public.can_read_ticket_file('../' || path1) then
    raise exception '10: Ungültiger Pfad lesbar';
  end if;

  -- 11) Anhängen ohne hochgeladene Datei schlägt fehl
  reset role;
  update public.ticket_requests set status = 'allocated' where id = r2;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.attach_ticket_file(r2);
  exception when others then failed := true;
  end;
  if not failed then raise exception '11: Anhängen ohne Datei möglich'; end if;

  reset role;
end;
$$;

select 'Alle Prüfungen bestanden' as result;

rollback;
