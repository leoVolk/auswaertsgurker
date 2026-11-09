import type { LeagueShortcut } from '../utils/leagues'

export interface LeagueTeam {
  teamId: number
  name: string
  shortName: string
}

export interface AwayMatch {
  matchId: number
  leagueShortcut: LeagueShortcut
  season: number
  matchday: number
  /** Heimmannschaft, bei der der Verein des Fanclubs antritt */
  opponentName: string
  /** Anstoß als ISO-String (UTC); `null`, solange der Spieltag nicht terminiert ist */
  kickoffAt: string | null
  /** Platzhalter-Termin aus OpenLigaDB bei offenem Termin (meist Samstag des Spielwochenendes) */
  provisionalAt: string | null
}
