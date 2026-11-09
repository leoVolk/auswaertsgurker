<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'

useHead({ title: 'Fanclub gründen' })

const createClub = useCreateClub()
const toast = useToast()
const showError = useErrorToast()

const state = reactive({ name: '' })

async function onSubmit(event: FormSubmitEvent<ClubNameForm>) {
  try {
    const clubId = await createClub(event.data.name)
    toast.add({
      title: 'Fanclub angelegt',
      description: 'Lade jetzt deine Mitglieder ein.',
      color: 'success',
      icon: 'i-lucide-check'
    })
    await navigateTo(`/clubs/${clubId}/members`)
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <div class="space-y-6">
    <div class="space-y-1">
      <h1 class="text-2xl font-bold text-highlighted">
        Fanclub gründen
      </h1>
      <p class="text-muted">
        Du wirst Organisator und kannst danach Mitglieder per Link einladen.
      </p>
    </div>

    <UCard>
      <UForm
        :schema="clubNameSchema"
        :state="state"
        class="space-y-4"
        @submit="onSubmit"
      >
        <UFormField
          name="name"
          label="Name des Fanclubs"
        >
          <UInput
            v-model="state.name"
            placeholder="z. B. Fanclub Nordkurve 1998"
            size="lg"
            class="w-full"
            autofocus
          />
        </UFormField>

        <UButton
          type="submit"
          label="Fanclub gründen"
          size="lg"
          block
          loading-auto
        />
      </UForm>
    </UCard>
  </div>
</template>
