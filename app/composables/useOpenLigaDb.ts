import type { AwayMatch } from '#shared/types/openligadb'
import type { ClubTeam } from './useClubs'

/** Vereine einer Liga (laufende Saison). */
export function useLeagueTeams(league: MaybeRefOrGetter<LeagueShortcut>) {
  return useFetch('/api/openligadb/teams', {
    query: computed(() => ({ league: toValue(league) })),
    default: () => []
  })
}

/** Kommende Auswärtsspiele des Vereins eines Fanclubs. */
export async function useAwayMatches(team: MaybeRefOrGetter<ClubTeam | null | undefined>) {
  const { data: matches, error, refresh } = await useAsyncData(
    () => {
      const value = toValue(team)
      return value ? `away-matches-${value.league}-${value.teamId}` : 'away-matches-none'
    },
    async (): Promise<AwayMatch[]> => {
      const value = toValue(team)
      if (!value) return []
      return await $fetch('/api/openligadb/away-matches', {
        query: { league: value.league, teamId: value.teamId }
      })
    },
    { default: () => [] }
  )

  return { matches, error, refresh }
}
