<script setup lang="ts">
defineProps<{
  /** `current-password` beim Login, `new-password` beim Festlegen (für Passwort-Manager) */
  autocomplete: 'current-password' | 'new-password'
}>()

const password = defineModel<string>({ required: true })
const show = ref(false)
</script>

<template>
  <UInput
    v-model="password"
    :type="show ? 'text' : 'password'"
    :autocomplete="autocomplete"
    size="lg"
    class="w-full"
    :ui="{ trailing: 'pe-1' }"
  >
    <template #trailing>
      <UButton
        color="neutral"
        variant="link"
        size="sm"
        :icon="show ? 'i-lucide-eye-off' : 'i-lucide-eye'"
        :aria-label="show ? 'Passwort verbergen' : 'Passwort anzeigen'"
        :aria-pressed="show"
        @click="show = !show"
      />
    </template>
  </UInput>
</template>
