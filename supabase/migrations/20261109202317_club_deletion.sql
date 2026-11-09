-- Fanclub endgültig löschen (Organisatoren) und Fanclub verlassen (Mitglieder)
--
-- Löschen: Alles Abhängige (Mitglieder, Einladungen, Spiele, Fahrten, Anmeldungen, Tickets,
-- Benachrichtigungen) verschwindet per Kaskade. Ticket-PDFs löscht der Client vorher über die
-- Storage-API. Die Trigger auf club_members erkennen das Löschen des Fanclubs und greifen nicht ein.

-- ---------------------------------------------------------------------------
-- Löschen
-- ---------------------------------------------------------------------------

grant delete on public.clubs to authenticated;

create policy "clubs_delete_organizers"
  on public.clubs for delete
  to authenticated
  using (public.is_club_organizer(id));

-- Was beim Löschen mit verschwindet; keine Zeile, wenn man kein Organisator ist
create function public.club_deletion_summary(p_club_id uuid)
returns table (
  members integer,
  trips integer,
  ticket_rounds integer,
  open_payments integer,
  ticket_files integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*) from public.club_members where club_id = p_club_id)::integer,
    (select count(*) from public.trips where club_id = p_club_id)::integer,
    (select count(*) from public.ticket_rounds where club_id = p_club_id)::integer,
    -- Bestätigte, nicht erstattete Zahlungen für kommende Spiele
    (
      (select count(*)
       from public.trip_registrations r
       join public.trips t on t.id = r.trip_id
       join public.away_games g on g.id = t.away_game_id
       where r.club_id = p_club_id
         and r.payment_status = 'confirmed'
         and (g.kickoff_at is null or g.kickoff_at > now()))
      +
      (select count(*)
       from public.ticket_requests q
       join public.ticket_rounds tr on tr.id = q.round_id
       join public.away_games g on g.id = tr.away_game_id
       where q.club_id = p_club_id
         and q.payment_status = 'confirmed'
         and (g.kickoff_at is null or g.kickoff_at > now()))
    )::integer,
    (select count(*) from public.ticket_requests where club_id = p_club_id and ticket_file_path is not null)::integer
  where public.is_club_organizer(p_club_id);
$$;

-- ---------------------------------------------------------------------------
-- Verlassen
-- ---------------------------------------------------------------------------

-- Mitglieder dürfen ihre eigene Mitgliedschaft löschen; der Trigger ensure_club_keeps_organizer
-- verhindert, dass der letzte Organisator geht
create policy "club_members_delete_self"
  on public.club_members for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- Austritt/Entfernen storniert Fahrt-Anmeldungen (Warteliste rückt nach) und offene Ticketanfragen.
-- Zugeteilte Tickets bleiben bestehen; um die kümmern sich die Organisatoren.
create or replace function public.cancel_registrations_of_removed_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip_id uuid;
begin
  -- Beim Löschen des ganzen Fanclubs räumt die Kaskade auf
  if not exists (select 1 from public.clubs where id = old.club_id) then
    return old;
  end if;

  for v_trip_id in
    update public.trip_registrations
    set status = 'cancelled',
        status_changed_at = now()
    where club_id = old.club_id
      and user_id = old.user_id
      and status <> 'cancelled'
    returning trip_id
  loop
    perform public.promote_trip_waitlist(v_trip_id);
  end loop;

  update public.ticket_requests
  set status = 'cancelled',
      status_changed_at = now()
  where club_id = old.club_id
    and requested_by = old.user_id
    and status in ('requested', 'waitlist');

  return old;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------

revoke execute on function public.club_deletion_summary(uuid) from public, anon, authenticated;
grant execute on function public.club_deletion_summary(uuid) to authenticated;
