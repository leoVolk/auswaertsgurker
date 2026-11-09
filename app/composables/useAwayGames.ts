import type { AwayMatch } from '#shared/types/openligadb'

/**
 * Legt das Auswärtsspiel eines Fanclubs an bzw. aktualisiert dessen Spieldaten und liefert die ID.
 * Anker für Fahrten und Ticketabfragen; nur für Organisatoren.
 */
export function useEnsureAwayGame() {
  const supabase = useSupabaseClient()

  return async (clubId: string, match: AwayMatch) => {
    const { data, error } = await supabase.rpc('ensure_away_game', {
      p_club_id: clubId,
      p_openligadb_match_id: match.matchId,
      p_league_shortcut: match.leagueShortcut,
      p_season: match.season,
      p_matchday: match.matchday,
      p_opponent_name: match.opponentName,
      // null = Termin offen (Platzhalter nicht speichern). Die generierten Typen kennen
      // kein null für RPC-Parameter; weglassen geht nicht, sonst findet PostgREST die Funktion nicht.
      p_kickoff_at: match.kickoffAt as string
    })
    if (error) throw error
    return data
  }
}
