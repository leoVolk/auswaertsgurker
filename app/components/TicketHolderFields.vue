<script setup lang="ts">
// Eingabefelder für Inhaber und Mitgliedsnummer (Pflicht); wird in UForm eingebettet
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
    required
    :help="`Sehen nur die Organisatoren. Wird ${TICKET_DATA_RETENTION_DAYS} Tage nach dem Spiel gelöscht.`"
  >
    <UInput
      v-model="membershipNumber"
      size="lg"
      class="w-full"
    />
  </UFormField>
</template>
