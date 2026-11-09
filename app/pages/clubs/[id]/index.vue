<script setup lang="ts">
const route = useRoute()
const clubId = computed(() => String(route.params.id))

const { club, isOrganizer } = await useClub(clubId)

useHead({ title: () => club.value?.name ?? 'Fanclub' })
</script>

<template>
  <UEmpty
    v-if="!club"
    icon="i-lucide-search-x"
    title="Fanclub nicht gefunden"
    description="Entweder stimmt der Link nicht oder du bist kein Mitglied dieses Fanclubs."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <ClubHeader :club="club" />

    <UEmpty
      icon="i-lucide-bus"
      title="Noch keine Fahrten"
      description="Hier erscheinen bald die Auswärtsfahrten deines Fanclubs."
    />

    <UButton
      :to="`/clubs/${club.id}/members`"
      :label="isOrganizer ? 'Mitglieder verwalten und einladen' : 'Mitglieder ansehen'"
      icon="i-lucide-users"
      trailing-icon="i-lucide-chevron-right"
      color="neutral"
      variant="outline"
      size="lg"
      block
      :ui="{ trailingIcon: 'ms-auto' }"
    />
  </div>
</template>
