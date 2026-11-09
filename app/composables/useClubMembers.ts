import type { ClubRole } from './useClubs'

export interface ClubMember {
  userId: string
  displayName: string
  role: ClubRole
}

export async function useClubMembers(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: members, error, refresh } = await useAsyncData(
    () => `club-members-${toValue(clubId)}`,
    async (): Promise<ClubMember[]> => {
      const id = toValue(clubId)
      if (!isUuid(id)) return []

      const { data, error } = await supabase
        .from('club_members')
        .select('user_id, role, profile:profiles!inner(display_name)')
        .eq('club_id', id)
      if (error) throw error

      return data
        .map(m => ({
          userId: m.user_id,
          displayName: m.profile.display_name ?? 'Ohne Namen',
          role: m.role
        }))
        // Organisatoren zuerst, dann alphabetisch
        .sort((a, b) =>
          Number(b.role === 'organizer') - Number(a.role === 'organizer')
          || a.displayName.localeCompare(b.displayName, 'de')
        )
    },
    { default: () => [] }
  )

  async function setRole(userId: string, role: ClubRole) {
    const { error } = await supabase
      .from('club_members')
      .update({ role })
      .eq('club_id', toValue(clubId))
      .eq('user_id', userId)
    if (error) throw error
    await refresh()
  }

  async function removeMember(userId: string) {
    const { error } = await supabase
      .from('club_members')
      .delete()
      .eq('club_id', toValue(clubId))
      .eq('user_id', userId)
    if (error) throw error
    await refresh()
  }

  return { members, error, refresh, setRole, removeMember }
}
