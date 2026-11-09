import type { serverSupabaseServiceRole } from '#supabase/server'
import type { Database } from '../../app/types/database.types'
import type { MatchResult } from './openligadb'

type ServiceClient = ReturnType<typeof serverSupabaseServiceRole<Database>>

const DAY_MS = 24 * 60 * 60 * 1000
const STORAGE_BATCH = 100

export interface PurgeSummary {
  checked: number
  purged: number
  requests: number
  files: number
  failed: number
}

/**
 * Löscht Mitgliedsnummern und Ticket-PDFs von Spielen, die laut OpenLigaDB beendet sind und
 * länger als die Löschfrist zurückliegen. Erst die Dateien (Storage-API), dann die DB-Verweise;
 * bricht ein Schritt ab, wiederholt der nächste Lauf ihn einfach.
 */
export async function purgeExpiredTicketData(supabase: ServiceClient, now = new Date()): Promise<PurgeSummary> {
  const { data: games, error } = await supabase
    .from('away_games')
    .select('id, openligadb_match_id, league_shortcut, season')
    .is('personal_data_purged_at', null)
  if (error) throw error

  const summary: PurgeSummary = { checked: games.length, purged: 0, requests: 0, files: 0, failed: 0 }
  const seasons = new Map<string, Map<number, MatchResult>>()

  for (const game of games) {
    if (!isLeagueShortcut(game.league_shortcut)) continue

    try {
      const seasonKey = `${game.league_shortcut}-${game.season}`
      let results = seasons.get(seasonKey)
      if (!results) {
        results = await getMatchResults(game.league_shortcut, game.season)
        seasons.set(seasonKey, results)
      }

      const match = results.get(game.openligadb_match_id)
      const ageMs = match ? now.getTime() - new Date(match.kickoffAt).getTime() : 0
      if (!match?.isFinished || ageMs < TICKET_DATA_RETENTION_DAYS * DAY_MS) continue

      const { data: rounds, error: roundsError } = await supabase
        .from('ticket_rounds')
        .select('id')
        .eq('away_game_id', game.id)
      if (roundsError) throw roundsError

      const roundIds = rounds.map(round => round.id)
      if (roundIds.length) {
        const { data: files, error: filesError } = await supabase
          .from('ticket_requests')
          .select('ticket_file_path')
          .in('round_id', roundIds)
          .not('ticket_file_path', 'is', null)
        if (filesError) throw filesError

        const paths = files.flatMap(file => (file.ticket_file_path ? [file.ticket_file_path] : []))
        for (let i = 0; i < paths.length; i += STORAGE_BATCH) {
          const { error: storageError } = await supabase.storage
            .from(TICKET_FILES_BUCKET)
            .remove(paths.slice(i, i + STORAGE_BATCH))
          if (storageError) throw storageError
        }
        summary.files += paths.length
      }

      const { data: count, error: purgeError } = await supabase.rpc('purge_away_game_ticket_data', {
        p_away_game_id: game.id,
        p_kickoff_at: match.kickoffAt
      })
      if (purgeError) throw purgeError

      summary.purged += 1
      summary.requests += count
    } catch (error) {
      // Ein fehlerhaftes Spiel blockiert die anderen nicht; nächster Lauf versucht es erneut
      console.error(`Löschfrist: Spiel ${game.id} fehlgeschlagen`, error)
      summary.failed += 1
    }
  }

  return summary
}
