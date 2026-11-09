<script setup lang="ts">
// Rückfallebene, falls die E-Mail noch einen Login-Link statt eines Codes enthält.
// Der Supabase-Client tauscht den Code aus der URL selbst gegen eine Session.
useHead({ title: 'Anmeldung' })

const userId = useCurrentUserId()
const cookieRedirect = useSupabaseCookieRedirect()
const router = useRouter()
const failed = ref(false)

watch(userId, (value) => {
  if (value) router.replace(safeRedirect(cookieRedirect.pluck()))
}, { immediate: true })

onMounted(() => {
  setTimeout(() => {
    if (!userId.value) failed.value = true
  }, 8000)
})
</script>

<template>
  <UEmpty
    v-if="failed"
    icon="i-lucide-link-2-off"
    title="Anmeldung hat nicht geklappt"
    description="Der Link aus der E-Mail funktioniert nur in dem Browser, in dem du ihn angefordert hast. Fordere bitte einen neuen Code an."
    :actions="[{ label: 'Zur Anmeldung', to: '/login' }]"
  />
  <UEmpty
    v-else
    loading
    title="Du wirst angemeldet …"
  />
</template>
