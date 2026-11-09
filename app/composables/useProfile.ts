import type { Tables } from '~/types/database.types'

export type Profile = Pick<Tables<'profiles'>, 'id' | 'display_name' | 'email_notifications'>

const PROFILE_COLUMNS = 'id, display_name, email_notifications'

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
      .select(PROFILE_COLUMNS)
      .eq('id', id)
      .single()
    if (error) throw error

    profile.value = data
    return data
  }

  async function update(changes: { display_name?: string, email_notifications?: boolean }) {
    const id = userId.value
    if (!id) throw new Error('Nicht angemeldet')

    const { data, error } = await supabase
      .from('profiles')
      .update(changes)
      .eq('id', id)
      .select(PROFILE_COLUMNS)
      .single()
    if (error) throw error

    profile.value = data
  }

  const updateDisplayName = (displayName: string) => update({ display_name: displayName })
  const updateEmailNotifications = (enabled: boolean) => update({ email_notifications: enabled })

  function clearProfile() {
    profile.value = null
  }

  return { profile, fetchProfile, updateDisplayName, updateEmailNotifications, clearProfile }
}
