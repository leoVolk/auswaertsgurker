export const LEAGUES = [
  { value: 'bl1', label: '1. Bundesliga' },
  { value: 'bl2', label: '2. Bundesliga' },
  { value: 'bl3', label: '3. Liga' }
] as const

export type LeagueShortcut = (typeof LEAGUES)[number]['value']

export const LEAGUE_SHORTCUTS = LEAGUES.map(league => league.value)

export function isLeagueShortcut(value: unknown): value is LeagueShortcut {
  return LEAGUE_SHORTCUTS.some(shortcut => shortcut === value)
}

export function leagueLabel(shortcut: LeagueShortcut) {
  return LEAGUES.find(league => league.value === shortcut)?.label ?? shortcut
}

/**
 * Laufende Saison nach OpenLigaDB-Zählung (2026 = Saison 2026/27).
 * Neue Saison ab 1. Juli.
 */
export function currentSeason(now = new Date()) {
  const year = now.getUTCFullYear()
  return now.getUTCMonth() >= 6 ? year : year - 1
}
