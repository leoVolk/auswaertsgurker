import type { ServiceClient } from './supabase'

/**
 * Gleicht die Anstoßzeiten der Auswärtsspiele mit OpenLigaDB ab. Ändert sich eine Zeit (oder steht
 * sie erstmals fest), benachrichtigt der DB-Trigger notify_kickoff_change alle Angemeldeten.
 */
export async function syncKickoffTimes(supabase: ServiceClient) {
  const { data: games, error } = await supabase
    .from('away_games')
    .select('id, openligadb_match_id, league_shortcut, season, kickoff_at')
    .is('personal_data_purged_at', null)
  if (error) throw error

  const seasons = new Map<string, Map<number, string | null>>()
  let updated = 0

  for (const game of games) {
    if (!isLeagueShortcut(game.league_shortcut)) continue

    const seasonKey = `${game.league_shortcut}-${game.season}`
    let kickoffs = seasons.get(seasonKey)
    if (!kickoffs) {
      kickoffs = await getScheduledKickoffs(game.league_shortcut, game.season)
      seasons.set(seasonKey, kickoffs)
    }

    const kickoff = kickoffs.get(game.openligadb_match_id)
    // Nicht (mehr) terminiert: gespeicherte Zeit nicht löschen
    if (!kickoff) continue
    if (game.kickoff_at && new Date(game.kickoff_at).getTime() === new Date(kickoff).getTime()) continue

    const { error: updateError } = await supabase
      .from('away_games')
      .update({ kickoff_at: kickoff })
      .eq('id', game.id)
    if (updateError) throw updateError
    updated += 1
  }

  return { checked: games.length, updated }
}
