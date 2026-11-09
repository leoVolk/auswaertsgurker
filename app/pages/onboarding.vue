<script setup lang="ts">
useHead({ title: 'Dein Name' })

const route = useRoute()
const { profile, fetchProfile, updateDisplayName } = useProfile()
const showError = useErrorToast()

await fetchProfile()

async function save(displayName: string) {
  try {
    await updateDisplayName(displayName)
    await navigateTo(safeRedirect(route.query.redirect))
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <div class="space-y-6">
    <div class="space-y-1">
      <h1 class="text-2xl font-bold text-highlighted">
        Willkommen! Wie heißt du?
      </h1>
      <p class="text-muted">
        Unter diesem Namen sehen dich die anderen in deinem Fanclub.
      </p>
    </div>

    <UCard>
      <DisplayNameForm
        :initial="profile?.display_name ?? ''"
        submit-label="Weiter"
        :save="save"
      />
    </UCard>
  </div>
</template>
