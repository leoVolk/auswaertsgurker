<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'

const props = defineProps<{
  initial: string
  submitLabel: string
  save: (displayName: string) => Promise<void>
}>()

const state = reactive({ displayName: props.initial })

async function onSubmit(event: FormSubmitEvent<DisplayNameForm>) {
  await props.save(event.data.displayName)
}
</script>

<template>
  <UForm
    :schema="displayNameSchema"
    :state="state"
    class="space-y-4"
    @submit="onSubmit"
  >
    <UFormField
      name="displayName"
      label="Name"
    >
      <UInput
        v-model="state.displayName"
        autocomplete="name"
        placeholder="z. B. Jonas M."
        size="lg"
        class="w-full"
      />
    </UFormField>

    <UButton
      type="submit"
      :label="submitLabel"
      size="lg"
      block
      loading-auto
    />
  </UForm>
</template>
