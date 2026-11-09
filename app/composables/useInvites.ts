/** Aktiver Einladungslink eines Fanclubs (nur für Organisatoren lesbar). */
export async function useClubInvite(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()
  const { origin } = useRequestURL()

  const { data: token, error } = await useAsyncData(
    () => `club-invite-${toValue(clubId)}`,
    async () => {
      const { data, error } = await supabase
        .from('club_invites')
        .select('token')
        .eq('club_id', toValue(clubId))
        .is('revoked_at', null)
        .maybeSingle()
      if (error) throw error
      return data?.token ?? null
    }
  )

  const link = computed(() => (token.value ? `${origin}/join/${token.value}` : null))

  /** Erzeugt einen neuen Link; der bisherige wird ungültig. */
  async function regenerate() {
    const { data, error } = await supabase.rpc('regenerate_invite', { p_club_id: toValue(clubId) })
    if (error) throw error
    token.value = data
  }

  return { link, error, regenerate }
}

export interface Invitation {
  clubId: string
  clubName: string
  isMember: boolean
}

/** Einladung über einen Link-Token; funktioniert auch ohne Login. */
export async function useInvitation(token: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: invitation, error, refresh } = await useAsyncData(
    () => `invitation-${toValue(token)}`,
    async (): Promise<Invitation | null> => {
      const { data, error } = await supabase.rpc('get_invite', { p_token: toValue(token) })
      if (error) throw error

      const row = data[0]
      return row ? { clubId: row.club_id, clubName: row.club_name, isMember: row.is_member } : null
    }
  )

  async function join() {
    const { data, error } = await supabase.rpc('join_club', { p_token: toValue(token) })
    if (error) throw error
    return data
  }

  return { invitation, error, refresh, join }
}
