<script setup lang="ts">
import type { NavigationMenuItem } from '@nuxt/ui'

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const route = useRoute()
const { profile, clearProfile } = useProfile()
const push = usePushNotifications()
const showError = useErrorToast()

const items = computed<NavigationMenuItem[][]>(() => [
  [
    {
      label: 'Meine Fanclubs',
      icon: 'i-lucide-users',
      to: '/',
      // Auch auf den Seiten eines Fanclubs hervorheben
      active: route.path === '/' || (route.path.startsWith('/clubs/') && route.path !== '/clubs/new')
    },
    { label: 'Meine Tickets', icon: 'i-lucide-ticket', to: '/tickets' },
    { label: 'Fanclub gründen', icon: 'i-lucide-plus', to: '/clubs/new' },
    { label: 'Profil & Benachrichtigungen', icon: 'i-lucide-user-cog', to: '/profile' }
  ],
  [{ label: 'Abmelden', icon: 'i-lucide-log-out', onSelect: signOut }]
])

async function signOut() {
  // Gerät soll nach dem Abmelden keine Push-Nachrichten dieses Kontos mehr bekommen
  if (push.subscribed.value) await push.unsubscribe().catch(() => {})
  const { error } = await supabase.auth.signOut()
  if (error) {
    showError(error)
    return
  }
  clearProfile()
  clearNuxtData()
  await navigateTo('/login')
}
</script>

<template>
  <div class="space-y-6">
    <UUser
      :name="profile?.display_name ?? 'Angemeldet'"
      :description="user?.email"
      :avatar="{ alt: profile?.display_name ?? undefined, icon: 'i-lucide-user' }"
      size="lg"
    />

    <UNavigationMenu
      :items="items"
      orientation="vertical"
      class="-mx-2.5"
    />
  </div>
</template>
