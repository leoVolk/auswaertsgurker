<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'

const supabase = useSupabaseClient()
const userId = useCurrentUserId()
const { profile, clearProfile } = useProfile()
const push = usePushNotifications()
const showError = useErrorToast()

const items = computed<DropdownMenuItem[][]>(() => [
  [{ type: 'label', label: profile.value?.display_name ?? 'Angemeldet' }],
  [
    { label: 'Meine Fanclubs', icon: 'i-lucide-users', to: '/' },
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
  <UDropdownMenu
    v-if="userId"
    :items="items"
    :content="{ align: 'end' }"
  >
    <UButton
      color="neutral"
      variant="ghost"
      :avatar="{ alt: profile?.display_name ?? undefined, icon: 'i-lucide-user' }"
      aria-label="Benutzermenü"
    />
  </UDropdownMenu>
</template>
