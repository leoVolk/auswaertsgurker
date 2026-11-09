-- Etappe 6: Löschfrist für personenbezogene Ticketdaten
--
-- Mitgliedsnummern und Ticket-PDFs werden 30 Tage nach dem Spiel gelöscht. Der tägliche Server-Job
-- (server/api/cron/cleanup.get.ts) löscht zuerst die Dateien über die Storage-API und ruft dann
-- purge_away_game_ticket_data auf. Nur mit dem Secret Key (service_role) aufrufbar.

alter table public.away_games
  add column personal_data_purged_at timestamptz;

create index away_games_not_purged_idx
  on public.away_games (id)
  where personal_data_purged_at is null;

-- Leert Mitgliedsnummern und PDF-Verweise aller Ticketanfragen eines Spiels und markiert es als
-- erledigt; liefert die Anzahl betroffener Anfragen. Mehrfaches Aufrufen schadet nicht.
create function public.purge_away_game_ticket_data(p_away_game_id uuid, p_kickoff_at timestamptz)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.ticket_requests q
  set holder_membership_number = null,
      ticket_file_path = null,
      ticket_file_uploaded_at = null
  from public.ticket_rounds r
  where r.id = q.round_id
    and r.away_game_id = p_away_game_id
    and (q.holder_membership_number is not null or q.ticket_file_path is not null);

  get diagnostics v_count = row_count;

  update public.away_games
  set personal_data_purged_at = now(),
      kickoff_at = coalesce(p_kickoff_at, kickoff_at)
  where id = p_away_game_id;

  return v_count;
end;
$$;

revoke execute on function public.purge_away_game_ticket_data(uuid, timestamptz)
from public, anon, authenticated;

grant execute on function public.purge_away_game_ticket_data(uuid, timestamptz) to service_role;
