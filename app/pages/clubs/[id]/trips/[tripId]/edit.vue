<script setup lang="ts">
import type { TripInput } from '~/composables/useTrips'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const tripId = computed(() => String(route.params.tripId))
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer } = await useClub(clubId)
const { trip: loadedTrip } = await useTrip(tripId)
const { updateTrip } = useTripActions(clubId)

const trip = computed(() => (loadedTrip.value?.clubId === clubId.value ? loadedTrip.value : null))

useHead({ title: 'Fahrt bearbeiten' })

async function save(input: TripInput) {
  try {
    await updateTrip(tripId.value, input)
    toast.add({ title: 'Änderungen gespeichert', color: 'success', icon: 'i-lucide-check' })
    await navigateTo(`/clubs/${clubId.value}/trips/${tripId.value}`, { replace: true })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UEmpty
    v-if="!club || !trip || !isOrganizer"
    icon="i-lucide-lock"
    title="Kein Zugriff"
    description="Die Fahrt gibt es nicht mehr oder nur Organisatoren dürfen sie bearbeiten."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <div class="space-y-2">
      <UButton
        :to="`/clubs/${club.id}/trips/${trip.id}`"
        label="Zurück zur Fahrt"
        icon="i-lucide-arrow-left"
        color="neutral"
        variant="link"
        class="-ms-2.5"
      />
      <h1 class="text-2xl font-bold text-highlighted">
        Fahrt bearbeiten
      </h1>
      <p class="text-sm font-medium text-highlighted">
        {{ trip.awayGame.matchday }}. Spieltag bei {{ trip.awayGame.opponentName }}
      </p>
    </div>

    <UCard>
      <TripForm
        :initial="trip"
        submit-label="Speichern"
        :save="save"
      />
    </UCard>
  </div>
</template>
