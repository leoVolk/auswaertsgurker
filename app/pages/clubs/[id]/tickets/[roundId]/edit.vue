<script setup lang="ts">
import type { TicketRoundInput } from '~/composables/useTickets'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const roundId = computed(() => String(route.params.roundId))
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer } = await useClub(clubId)
const { round: loadedRound } = await useTicketRound(roundId)
const { updateRound } = useTicketRoundActions(clubId)

const round = computed(() => (loadedRound.value?.clubId === clubId.value ? loadedRound.value : null))

const initial = computed<TicketRoundInput | undefined>(() => round.value
  ? {
      requestDeadline: round.value.requestDeadline,
      maxTicketsPerMember: round.value.maxTicketsPerMember,
      membershipNumberRequired: round.value.membershipNumberRequired,
      downloadRequiresPayment: round.value.downloadRequiresPayment,
      notes: round.value.notes,
      categories: round.value.categories
    }
  : undefined)

useHead({ title: 'Ticketabfrage bearbeiten' })

async function save(input: TicketRoundInput) {
  if (!round.value) return
  try {
    await updateRound(round.value.id, input, round.value.categories)
    toast.add({ title: 'Änderungen gespeichert', color: 'success', icon: 'i-lucide-check' })
    await navigateTo(`/clubs/${clubId.value}/tickets/${roundId.value}`, { replace: true })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UEmpty
    v-if="!club || !round || !isOrganizer"
    icon="i-lucide-lock"
    title="Kein Zugriff"
    description="Die Ticketabfrage gibt es nicht mehr oder nur Organisatoren dürfen sie bearbeiten."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <div class="space-y-2">
      <UButton
        :to="`/clubs/${club.id}/tickets/${round.id}`"
        label="Zurück zur Ticketabfrage"
        icon="i-lucide-arrow-left"
        color="neutral"
        variant="link"
        class="-ms-2.5"
      />
      <h1 class="text-2xl font-bold text-highlighted">
        Ticketabfrage bearbeiten
      </h1>
      <p class="text-sm font-medium text-highlighted">
        {{ round.awayGame.matchday }}. Spieltag bei {{ round.awayGame.opponentName }}
      </p>
    </div>

    <UCard>
      <TicketRoundForm
        :initial="initial"
        submit-label="Speichern"
        :save="save"
      />
    </UCard>
  </div>
</template>
