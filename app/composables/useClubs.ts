import type { Enums } from '~/types/database.types'

export type ClubRole = Enums<'club_role'>

export interface ClubMembership {
  id: string
  name: string
  role: ClubRole
}

export const ROLE_LABELS: Record<ClubRole, string> = {
  organizer: 'Organisator',
  member: 'Mitglied'
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
        .select('role, club:clubs!inner(id, name)')
        .eq('user_id', userId.value)
        .order('joined_at')
      if (error) throw error

      return data.map(m => ({ id: m.club.id, name: m.club.name, role: m.role }))
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
        .select('role, club:clubs!inner(id, name)')
        .eq('club_id', id)
        .eq('user_id', userId.value)
        .maybeSingle()
      if (error) throw error

      return data ? { id: data.club.id, name: data.club.name, role: data.role } : null
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
