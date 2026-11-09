<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'

useHead({ title: 'Dein Name' })

const route = useRoute()
const { profile, fetchProfile, updateDisplayName } = useProfile()
const showError = useErrorToast()

await fetchProfile()

const isFirstVisit = !profile.value?.display_name
const state = reactive({ displayName: profile.value?.display_name ?? '' })

async function onSubmit(event: FormSubmitEvent<DisplayNameForm>) {
  try {
    await updateDisplayName(event.data.displayName)
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
        {{ isFirstVisit ? 'Willkommen! Wie heißt du?' : 'Namen ändern' }}
      </h1>
      <p class="text-muted">
        Unter diesem Namen sehen dich die anderen in deinem Fanclub.
      </p>
    </div>

    <UCard>
      <UForm
        :schema="displayNameSchema"
        :state="state"
        class="space-y-4"
        @submit="onSubmit"
      >
        <UFormField
          name="displayName"
          label="Name"
          help="Am besten so, wie man dich in der Kurve kennt."
        >
          <UInput
            v-model="state.displayName"
            autocomplete="name"
            placeholder="z. B. Jonas M."
            size="lg"
            class="w-full"
            autofocus
          />
        </UFormField>

        <UButton
          type="submit"
          :label="isFirstVisit ? 'Weiter' : 'Speichern'"
          size="lg"
          block
          loading-auto
        />
      </UForm>
    </UCard>
  </div>
</template>
