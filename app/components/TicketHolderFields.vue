<script setup lang="ts">
// Eingabefelder für Inhaber und Mitgliedsnummer; wird in UForm eingebettet
defineProps<{
  membershipNumberRequired: boolean
}>()

const holderName = defineModel<string>('holderName', { required: true })
const membershipNumber = defineModel<string>('membershipNumber', { required: true })
</script>

<template>
  <UFormField
    name="holderName"
    label="Name des Inhabers"
    help="So, wie er auf dem Ticket stehen soll."
  >
    <UInput
      v-model="holderName"
      autocomplete="name"
      size="lg"
      class="w-full"
    />
  </UFormField>

  <UFormField
    name="membershipNumber"
    label="Mitgliedsnummer"
    :hint="membershipNumberRequired ? undefined : 'Optional'"
    :required="membershipNumberRequired"
    help="Vereinsmitgliedsnummer des Inhabers. Nur für Organisatoren sichtbar."
  >
    <UInput
      v-model="membershipNumber"
      size="lg"
      class="w-full"
    />
  </UFormField>
</template>
