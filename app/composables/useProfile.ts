import type { Tables } from '~/types/database.types'

export type Profile = Pick<Tables<'profiles'>, 'id' | 'display_name'>

export function useProfile() {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()
  const profile = useState<Profile | null>('profile', () => null)

  async function fetchProfile() {
    const id = userId.value
    if (!id) {
      profile.value = null
      return null
    }
    if (profile.value?.id === id) {
      return profile.value
    }

    const { data, error } = await supabase
      .from('profiles')
      .select('id, display_name')
      .eq('id', id)
      .single()
    if (error) throw error

    profile.value = data
    return data
  }

  async function updateDisplayName(displayName: string) {
    const id = userId.value
    if (!id) throw new Error('Nicht angemeldet')

    const { data, error } = await supabase
      .from('profiles')
      .update({ display_name: displayName })
      .eq('id', id)
      .select('id, display_name')
      .single()
    if (error) throw error

    profile.value = data
  }

  function clearProfile() {
    profile.value = null
  }

  return { profile, fetchProfile, updateDisplayName, clearProfile }
}
