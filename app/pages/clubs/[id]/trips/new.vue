<script setup lang="ts">
import type { TripInput } from '~/composables/useTrips'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const matchId = computed(() => Number(route.query.match))
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer } = await useClub(clubId)
const { matches } = await useAwayMatches(() => club.value?.team)
const { createTrip } = useTripActions(clubId)

const match = computed(() => matches.value.find(m => m.matchId === matchId.value) ?? null)

useHead({ title: 'Fahrt planen' })

async function save(input: TripInput) {
  if (!match.value) return
  try {
    const tripId = await createTrip(match.value, input)
    toast.add({ title: 'Fahrt angelegt', color: 'success', icon: 'i-lucide-check' })
    await navigateTo(`/clubs/${clubId.value}/trips/${tripId}`, { replace: true })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UEmpty
    v-if="!club || !isOrganizer"
    icon="i-lucide-lock"
    title="Kein Zugriff"
    description="Nur Organisatoren können Fahrten planen."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <UEmpty
    v-else-if="!match"
    icon="i-lucide-calendar-x"
    title="Spiel nicht gefunden"
    description="Das Spiel steht nicht mehr im Spielplan oder ist schon vorbei."
    :actions="[{ label: 'Zurück zum Fanclub', to: `/clubs/${club.id}` }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <div class="space-y-2">
      <UButton
        :to="`/clubs/${club.id}`"
        label="Zurück zum Fanclub"
        icon="i-lucide-arrow-left"
        color="neutral"
        variant="link"
        class="-ms-2.5"
      />
      <h1 class="text-2xl font-bold text-highlighted">
        Fahrt planen
      </h1>
      <div class="space-y-1 text-sm">
        <p class="font-medium text-highlighted">
          {{ match.matchday }}. Spieltag bei {{ match.opponentName }}
        </p>
        <KickoffLabel
          :kickoff-at="match.kickoffAt"
          :provisional-at="match.provisionalAt"
        />
      </div>
    </div>

    <UCard>
      <TripForm
        submit-label="Fahrt anlegen"
        :save="save"
      />
    </UCard>
  </div>
</template>
