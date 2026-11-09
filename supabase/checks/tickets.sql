-- Logiktest für Ticketabfragen (Etappe 4).
-- Läuft komplett in einer Transaktion und wird am Ende zurückgerollt, hinterlässt also keine Daten.
-- Ausführen: pnpm exec supabase db query --remote --yes -f supabase/checks/tickets.sql
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
  round uuid;
  cat_a uuid;
  cat_b uuid;
  r_u1_1 uuid;
  r_u1_2 uuid;
  r_u2 uuid;
  r_u3 uuid;
  r_u2_b uuid;
  n integer;
  s public.ticket_status;
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

  set local role authenticated;

  -- 0) Mitglied darf keine Abfrage anlegen
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    insert into public.ticket_rounds (club_id, away_game_id) values (club, game);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception '0: Mitglied konnte Ticketabfrage anlegen'; end if;

  -- Organisator legt Abfrage mit zwei Kategorien an
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  insert into public.ticket_rounds (club_id, away_game_id, request_deadline, max_tickets_per_member)
  values (club, game, now() + interval '1 day', 2)
  returning id into round;
  insert into public.ticket_categories (round_id, club_id, name, price_cents, quota, sort_order)
  values (round, club, 'Stehplatz', 1800, 2, 0)
  returning id into cat_a;
  insert into public.ticket_categories (round_id, club_id, name, price_cents, quota, sort_order)
  values (round, club, 'Sitzplatz', 3500, null, 1)
  returning id into cat_b;

  -- 1) u1 fragt zwei Tickets an, das dritte überschreitet den Höchstwert
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  r_u1_1 := public.request_ticket(cat_a, 'Max Muster', null);
  r_u1_2 := public.request_ticket(cat_a, 'Erika Muster', '12345');
  failed := false;
  begin
    perform public.request_ticket(cat_a, 'Dritte Person', null);
  exception when others then failed := true;
  end;
  if not failed then raise exception '1: Höchstwert pro Mitglied nicht durchgesetzt'; end if;

  -- 2) u2 und u3 fragen je ein Ticket an
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  r_u2 := public.request_ticket(cat_a, 'Zweiter', null);
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  r_u3 := public.request_ticket(cat_a, 'Dritter', null);

  -- 3) RLS: u3 sieht nur die eigene Anfrage
  select count(*) into n from public.ticket_requests;
  if n <> 1 then raise exception '3: u3 sieht % Anfragen statt 1', n; end if;

  -- 4) u2 storniert die eigene Anfrage
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  perform public.cancel_ticket_request(r_u2);
  select status into s from public.ticket_requests where id = r_u2;
  if s <> 'cancelled' then raise exception '4: Stornierung fehlgeschlagen (%)', s; end if;

  -- 5) Mitglied darf keinen Status setzen
  failed := false;
  begin
    perform public.set_ticket_request_status(r_u3, 'allocated');
  exception when others then failed := true;
  end;
  if not failed then raise exception '5: Mitglied konnte zuteilen'; end if;

  -- 6) Automatisch zuteilen: zwei älteste Anfragen bekommen Tickets, u3 kommt auf die Warteliste
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  select * into rec from public.auto_allocate_tickets(cat_a);
  if rec.allocated <> 2 or rec.waitlisted <> 1 then raise exception '6a: Zuteilung %', rec; end if;
  select status into s from public.ticket_requests where id = r_u3;
  if s <> 'waitlist' then raise exception '6b: u3 nicht auf der Warteliste (%)', s; end if;

  -- 7) Kontingent ausgeschöpft
  failed := false;
  begin
    perform public.set_ticket_request_status(r_u3, 'allocated');
  exception when others then failed := true;
  end;
  if not failed then raise exception '7: Kontingent überbucht'; end if;

  -- 8) Mitglied kann zugeteiltes Ticket nicht stornieren
  perform set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.cancel_ticket_request(r_u1_1);
  exception when others then failed := true;
  end;
  if not failed then raise exception '8: Mitglied konnte zugeteiltes Ticket stornieren'; end if;

  -- 9) Organisator storniert ein Ticket von u1 und teilt es u3 zu
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  perform public.cancel_ticket_request(r_u1_2);
  perform public.set_ticket_request_status(r_u3, 'allocated');
  select status into s from public.ticket_requests where id = r_u3;
  if s <> 'allocated' then raise exception '9: u3 nicht zugeteilt (%)', s; end if;

  -- 10) Automatisch zuteilen ohne Kontingent geht nicht
  failed := false;
  begin
    perform public.auto_allocate_tickets(cat_b);
  exception when others then failed := true;
  end;
  if not failed then raise exception '10: Zuteilung ohne Kontingent möglich'; end if;

  -- 11) Mitgliedsnummer erforderlich
  update public.ticket_rounds set membership_number_required = true where id = round;
  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.request_ticket(cat_b, 'Ohne Nummer', '  ');
  exception when others then failed := true;
  end;
  if not failed then raise exception '11a: Anfrage ohne Pflicht-Mitgliedsnummer möglich'; end if;
  r_u2_b := public.request_ticket(cat_b, 'Mit Nummer', 'M-42');

  -- 12) Inhaber ändern: vor Zuteilung ja, danach nur Organisator
  perform public.update_ticket_request_holder(r_u2_b, 'Neuer Name', 'M-43');
  select holder_membership_number into rec from public.ticket_requests where id = r_u2_b;
  if rec.holder_membership_number <> 'M-43' then raise exception '12a: Inhaber nicht geändert'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  perform public.set_ticket_request_status(r_u2_b, 'allocated');

  perform set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.update_ticket_request_holder(r_u2_b, 'Weiterverkauft', 'M-44');
  exception when others then failed := true;
  end;
  if not failed then raise exception '12b: Mitglied konnte Inhaber nach Zuteilung ändern'; end if;

  -- 13) Geschlossene Abfrage nimmt keine Anfragen an
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  update public.ticket_rounds set closed_at = now() where id = round;
  perform set_config('request.jwt.claims', json_build_object('sub', u3, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.request_ticket(cat_b, 'Zu spät', 'M-1');
  exception when others then failed := true;
  end;
  if not failed then raise exception '13: Anfrage trotz geschlossener Abfrage möglich'; end if;

  -- 14) Kategorie mit Anfragen lässt sich nicht löschen
  perform set_config('request.jwt.claims', json_build_object('sub', orga, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    delete from public.ticket_categories where id = cat_a;
  exception when foreign_key_violation then failed := true;
  end;
  if not failed then raise exception '14: Kategorie mit Anfragen gelöscht'; end if;

  -- 15) Abfrage samt Kategorien und Anfragen löschen
  delete from public.ticket_rounds where id = round;
  reset role;
  select count(*) into n from public.ticket_requests where round_id = round;
  if n <> 0 then raise exception '15: % Anfragen nach dem Löschen übrig', n; end if;
end;
$$;

select 'Alle Prüfungen bestanden' as result;

rollback;
