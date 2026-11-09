// Wer angemeldet ist, aber noch keinen Namen hat, landet zuerst im Onboarding
const SKIPPED_PATHS = ['/onboarding', '/login', '/confirm']

export default defineNuxtRouteMiddleware(async (to) => {
  const userId = useCurrentUserId()
  if (!userId.value || SKIPPED_PATHS.includes(to.path)) return

  const { fetchProfile } = useProfile()
  const profile = await fetchProfile()

  if (!profile?.display_name) {
    return navigateTo({ path: '/onboarding', query: { redirect: to.fullPath } })
  }
})
