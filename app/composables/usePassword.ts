/**
 * Ob der User ein Passwort festgelegt hat. Supabase verrät das nicht, deshalb setzt
 * `useSetPassword` eine Markierung in den `user_metadata` (nur ein Hinweis für die Oberfläche).
 */
export function useHasPassword() {
  const user = useSupabaseUser()

  return computed(() => user.value?.user_metadata?.has_password === true)
}

/** Passwort festlegen oder ändern; die Anmeldung per Code funktioniert weiterhin. */
export function useSetPassword() {
  const supabase = useSupabaseClient()
  const syncUser = useSyncSupabaseUser()

  return async (password: string) => {
    const { error } = await supabase.auth.updateUser({ password, data: { has_password: true } })
    if (error) throw error

    // Die Markierung steht im Token: neu ausstellen lassen, damit die Oberfläche sie sofort kennt.
    // Schlägt das fehl, ist das Passwort trotzdem gespeichert; die Markierung kommt dann mit dem nächsten Token.
    await supabase.auth.refreshSession()
    await syncUser().catch(() => {})
  }
}
