/**
 * ID des angemeldeten Users.
 * `useSupabaseUser()` liefert JWT-Claims (ID in `sub`, nicht `id`).
 */
export function useCurrentUserId() {
  const user = useSupabaseUser()

  return computed(() => user.value?.sub ?? null)
}

/**
 * Das Modul setzt den User nach einem Login erst asynchron.
 * Vor einer Weiterleitung aufrufen, damit Middleware und Seiten den User sofort kennen.
 */
export function useSyncSupabaseUser() {
  const supabase = useSupabaseClient()
  const user = useSupabaseUser()

  return async () => {
    const { data, error } = await supabase.auth.getClaims()
    if (error) throw error
    user.value = data?.claims ?? null
  }
}
