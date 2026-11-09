import type { AwayMatch, LeagueTeam } from '#shared/types/openligadb'
import type { LeagueShortcut } from '#shared/utils/leagues'

const BASE_URL = 'https://api.openligadb.de'

interface OldbTeam {
  teamId: number
  teamName: string
  shortName: string
}

interface OldbMatch {
  matchID: number
  matchDateTimeUTC: string
  leagueShortcut: string
  leagueSeason: number
  group: { groupOrderID: number }
  team1: OldbTeam
  team2: OldbTeam
  matchIsFinished: boolean
}

const fetchSeasonMatches = defineCachedFunction(
  (league: LeagueShortcut, season: number) =>
    $fetch<OldbMatch[]>(`${BASE_URL}/getmatchdata/${league}/${season}`, { timeout: 10_000 }),
  {
    name: 'openligadb-season-matches',
    maxAge: 60 * 10,
    swr: true,
    getKey: (league: LeagueShortcut, season: number) => `${league}-${season}`
  }
)

const fetchLeagueTeams = defineCachedFunction(
  (league: LeagueShortcut, season: number) =>
    $fetch<OldbTeam[]>(`${BASE_URL}/getavailableteams/${league}/${season}`, { timeout: 10_000 }),
  {
    name: 'openligadb-league-teams',
    maxAge: 60 * 60 * 24,
    swr: true,
    getKey: (league: LeagueShortcut, season: number) => `${league}-${season}`
  }
)

export async function getLeagueTeams(league: LeagueShortcut, season: number): Promise<LeagueTeam[]> {
  const teams = await fetchLeagueTeams(league, season)
  return teams
    .map(team => ({ teamId: team.teamId, name: team.teamName, shortName: team.shortName }))
    .sort((a, b) => a.name.localeCompare(b.name, 'de'))
}

/**
 * Kommende Auswärtsspiele eines Vereins.
 *
 * OpenLigaDB kennzeichnet nicht terminierte Spieltage nicht ausdrücklich, sondern setzt alle
 * Spiele auf denselben Platzhalter (Samstag 15:30). Ein Spieltag gilt daher als terminiert,
 * sobald seine Spiele unterschiedliche Anstoßzeiten haben. Ausnahme: Am letzten Spieltag
 * spielen alle gleichzeitig.
 */
export async function getUpcomingAwayMatches(
  league: LeagueShortcut,
  season: number,
  teamId: number
): Promise<AwayMatch[]> {
  const matches = await fetchSeasonMatches(league, season)

  const kickoffsByMatchday = new Map<number, Set<string>>()
  let lastMatchday = 0
  for (const match of matches) {
    const matchday = match.group.groupOrderID
    lastMatchday = Math.max(lastMatchday, matchday)
    const kickoffs = kickoffsByMatchday.get(matchday) ?? new Set<string>()
    kickoffs.add(match.matchDateTimeUTC)
    kickoffsByMatchday.set(matchday, kickoffs)
  }

  const isScheduled = (matchday: number) =>
    matchday === lastMatchday || (kickoffsByMatchday.get(matchday)?.size ?? 0) > 1

  return matches
    .filter(match => match.team2.teamId === teamId && !match.matchIsFinished)
    .map((match) => {
      const matchday = match.group.groupOrderID
      const scheduled = isScheduled(matchday)
      return {
        matchId: match.matchID,
        leagueShortcut: league,
        season,
        matchday,
        opponentName: match.team1.teamName,
        kickoffAt: scheduled ? match.matchDateTimeUTC : null,
        provisionalAt: scheduled ? null : match.matchDateTimeUTC
      }
    })
    .sort((a, b) => a.matchday - b.matchday)
}
