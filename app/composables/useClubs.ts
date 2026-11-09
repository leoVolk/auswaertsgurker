import type { Enums, Tables } from '~/types/database.types'

export type ClubRole = Enums<'club_role'>

export interface ClubTeam {
  league: LeagueShortcut
  teamId: number
  name: string
}

export interface ClubMembership {
  id: string
  name: string
  role: ClubRole
  team: ClubTeam | null
  /** PayPal.Me-Name des Fanclubs */
  paypalMe: string | null
}

export const ROLE_LABELS: Record<ClubRole, string> = {
  organizer: 'Organisator',
  member: 'Mitglied'
}

const CLUB_COLUMNS = 'id, name, league_shortcut, team_id, team_name, paypal_me'

type ClubRow = Pick<Tables<'clubs'>, 'id' | 'name' | 'league_shortcut' | 'team_id' | 'team_name' | 'paypal_me'>

function toMembership(club: ClubRow, role: ClubRole): ClubMembership {
  const team = isLeagueShortcut(club.league_shortcut) && club.team_id && club.team_name
    ? { league: club.league_shortcut, teamId: club.team_id, name: club.team_name }
    : null
  return { id: club.id, name: club.name, role, team, paypalMe: club.paypal_me }
}

/** Alle Fanclubs, in denen der angemeldete User Mitglied ist. */
export async function useMyClubs() {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()

  const { data: clubs, error, refresh } = await useAsyncData(
    'my-clubs',
    async (): Promise<ClubMembership[]> => {
      if (!userId.value) return []

      const { data, error } = await supabase
        .from('club_members')
        .select(`role, club:clubs!inner(${CLUB_COLUMNS})`)
        .eq('user_id', userId.value)
        .order('joined_at')
      if (error) throw error

      return data.map(m => toMembership(m.club, m.role))
    },
    { default: () => [] }
  )

  return { clubs, error, refresh }
}

/** Ein einzelner Fanclub samt eigener Rolle; `null`, wenn man kein Mitglied ist. */
export async function useClub(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()

  const { data: club, error, refresh } = await useAsyncData(
    () => `club-${toValue(clubId)}`,
    async (): Promise<ClubMembership | null> => {
      const id = toValue(clubId)
      if (!userId.value || !isUuid(id)) return null

      const { data, error } = await supabase
        .from('club_members')
        .select(`role, club:clubs!inner(${CLUB_COLUMNS})`)
        .eq('club_id', id)
        .eq('user_id', userId.value)
        .maybeSingle()
      if (error) throw error

      return data ? toMembership(data.club, data.role) : null
    }
  )

  const isOrganizer = computed(() => club.value?.role === 'organizer')

  return { club, isOrganizer, error, refresh }
}

export function useCreateClub() {
  const supabase = useSupabaseClient()

  return async (name: string) => {
    const { data, error } = await supabase.rpc('create_club', { p_name: name })
    if (error) throw error
    return data
  }
}

export function useUpdateClub() {
  const supabase = useSupabaseClient()

  return async (clubId: string, input: { name: string, team: ClubTeam, paypalMe: string | null }) => {
    const { error } = await supabase
      .from('clubs')
      .update({
        name: input.name,
        league_shortcut: input.team.league,
        team_id: input.team.teamId,
        team_name: input.team.name,
        paypal_me: input.paypalMe
      })
      .eq('id', clubId)
    if (error) throw error
  }
}
