/**
 * Eigene Vereinsmitgliedsnummer (eine pro Person) zum Vorausfüllen von Ticketanfragen.
 * Liegt in membership_numbers statt in profiles, weil Profile für alle Mitglieder gemeinsamer
 * Fanclubs lesbar sind; geschrieben wird nur über die RPC set_my_membership_number.
 */
export async function useMembershipNumber() {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()

  const { data: membershipNumber, refresh } = await useAsyncData(
    () => `membership-number-${userId.value}`,
    async () => {
      if (!userId.value) return null
      const { data, error } = await supabase
        .from('membership_numbers')
        .select('membership_number')
        .eq('user_id', userId.value)
        .maybeSingle()
      if (error) throw error
      return data?.membership_number ?? null
    },
    { default: () => null }
  )

  /** Speichert die Nummer; ein leerer Wert löscht sie. */
  async function save(value: string) {
    const { error } = await supabase.rpc('set_my_membership_number', { p_membership_number: value.trim() })
    if (error) throw error
    await refresh()
  }

  return { membershipNumber, save }
}
