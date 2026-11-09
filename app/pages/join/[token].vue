<script setup lang="ts">
// Öffentliche Seite (in nuxt.config von der Login-Pflicht ausgenommen)
useHead({ title: 'Einladung' })

const route = useRoute()
const token = computed(() => String(route.params.token))
const userId = useCurrentUserId()
const cookieRedirect = useSupabaseCookieRedirect()
const toast = useToast()
const showError = useErrorToast()

const { invitation, error, join } = await useInvitation(token)

async function goToLogin() {
  // Nach dem Login zurück auf diese Seite
  cookieRedirect.path.value = route.fullPath
  await navigateTo('/login')
}

async function onJoin() {
  try {
    const clubId = await join()
    toast.add({
      title: `Willkommen bei ${invitation.value?.clubName ?? 'deinem Fanclub'}!`,
      color: 'success',
      icon: 'i-lucide-party-popper'
    })
    await navigateTo(`/clubs/${clubId}`)
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UAlert
    v-if="error"
    color="error"
    variant="subtle"
    icon="i-lucide-circle-alert"
    title="Die Einladung konnte nicht geladen werden."
    description="Prüfe deine Verbindung und lade die Seite neu."
  />

  <UEmpty
    v-else-if="!invitation"
    icon="i-lucide-link-2-off"
    title="Einladung ungültig"
    description="Dieser Link ist ungültig oder wurde durch einen neuen ersetzt. Frag in deiner WhatsApp-Gruppe nach dem aktuellen Link."
  />

  <UCard v-else>
    <div class="flex flex-col items-center gap-6 py-4 text-center">
      <UIcon
        name="i-lucide-flag"
        class="size-10 text-primary"
      />

      <div class="space-y-1">
        <p class="text-muted">
          Du bist eingeladen zum Fanclub
        </p>
        <h1 class="text-2xl font-bold text-highlighted">
          {{ invitation.clubName }}
        </h1>
      </div>

      <div
        v-if="!userId"
        class="w-full space-y-3"
      >
        <UButton
          label="Anmelden und beitreten"
          size="lg"
          block
          @click="goToLogin"
        />
        <p class="text-sm text-muted">
          Du bekommst einen Code per E-Mail. Ein Passwort brauchst du nicht.
        </p>
      </div>

      <UButton
        v-else-if="invitation.isMember"
        :to="`/clubs/${invitation.clubId}`"
        label="Du bist schon dabei – zum Fanclub"
        size="lg"
        block
      />

      <UButton
        v-else
        label="Fanclub beitreten"
        size="lg"
        block
        loading-auto
        @click="onJoin"
      />
    </div>
  </UCard>
</template>
