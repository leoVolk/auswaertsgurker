<script setup lang="ts">
import type { TicketRoundInput } from '~/composables/useTickets'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const matchId = computed(() => Number(route.query.match))
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer } = await useClub(clubId)
const { matches } = await useAwayMatches(() => club.value?.team)
const { createRound } = useTicketRoundActions(clubId)

const match = computed(() => matches.value.find(m => m.matchId === matchId.value) ?? null)

useHead({ title: 'Ticketabfrage öffnen' })

async function save(input: TicketRoundInput) {
  if (!match.value) return
  try {
    const roundId = await createRound(match.value, input)
    toast.add({ title: 'Ticketabfrage geöffnet', color: 'success', icon: 'i-lucide-check' })
    await navigateTo(`/clubs/${clubId.value}/tickets/${roundId}`, { replace: true })
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
    description="Nur Organisatoren können Ticketabfragen öffnen."
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
        Ticketabfrage öffnen
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
      <TicketRoundForm
        submit-label="Ticketabfrage öffnen"
        :save="save"
      />
    </UCard>
  </div>
</template>
