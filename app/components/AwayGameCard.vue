<script setup lang="ts">
import type { AwayMatch } from '#shared/types/openligadb'
import type { TicketRoundSummary, TicketStatus } from '~/composables/useTickets'
import type { TripStats } from '~/composables/useTripRegistrations'
import type { TripSummary } from '~/composables/useTrips'

const props = defineProps<{
  clubId: string
  match: AwayMatch
  trips: TripSummary[]
  stats: Map<string, TripStats>
  ticketRound?: TicketRoundSummary
  isOrganizer: boolean
}>()

function tripMeta(trip: TripSummary) {
  const departure = trip.departureAt ? `Abfahrt ${formatDateTime(trip.departureAt)}` : 'Abfahrt noch offen'
  const taken = props.stats.get(trip.id)?.takenSeats ?? 0
  const seats = trip.capacity ? `${taken}/${trip.capacity} Plätze` : `${taken} dabei`
  return `${departure} · ${seats}`
}

function myTripStatus(trip: TripSummary) {
  const status = props.stats.get(trip.id)?.myStatus
  return status && status !== 'cancelled' ? REGISTRATION_STATUS[status] : null
}

const ticketMeta = computed(() => {
  const round = props.ticketRound
  if (!round) return ''
  if (!isTicketRoundOpen(round)) return 'Abfrage geschlossen'
  return round.requestDeadline ? `Anfragen bis ${formatDateTime(round.requestDeadline)}` : 'Anfragen möglich'
})

// Eigene Anfragen zusammengefasst, z. B. „2× Zugeteilt“
const myTicketBadges = computed(() => {
  const counts = new Map<TicketStatus, number>()
  for (const status of props.ticketRound?.myStatuses ?? []) {
    if (status === 'cancelled') continue
    counts.set(status, (counts.get(status) ?? 0) + 1)
  }
  return [...counts].map(([status, count]) => ({
    label: `${count}× ${TICKET_STATUS[status].label}`,
    color: TICKET_STATUS[status].color
  }))
})
</script>

<template>
  <UCard :ui="{ body: 'space-y-5' }">
    <div class="space-y-1">
      <p class="text-sm text-muted">
        {{ match.matchday }}. Spieltag
      </p>
      <h3 class="text-lg font-semibold text-highlighted">
        bei {{ match.opponentName }}
      </h3>
      <KickoffLabel
        :kickoff-at="match.kickoffAt"
        :provisional-at="match.provisionalAt"
        class="text-sm"
      />
    </div>

    <section class="space-y-2">
      <h4 class="text-xs font-semibold tracking-wide text-muted uppercase">
        Fahrten
      </h4>
      <ul
        v-if="trips.length"
        class="divide-y divide-default rounded-md border border-default"
      >
        <li
          v-for="trip in trips"
          :key="trip.id"
        >
          <NuxtLink
            :to="`/clubs/${clubId}/trips/${trip.id}`"
            class="flex items-center gap-3 px-3 py-2.5 transition-colors hover:bg-elevated/50"
          >
            <UIcon
              :name="TRANSPORT_MODES[trip.transport].icon"
              class="size-5 shrink-0 text-primary"
            />
            <span class="min-w-0 flex-1">
              <span class="block truncate font-medium text-highlighted">{{ tripLabel(trip) }}</span>
              <span class="block text-sm text-muted">{{ tripMeta(trip) }}</span>
            </span>
            <UBadge
              v-if="myTripStatus(trip)"
              :label="myTripStatus(trip)?.label"
              :color="myTripStatus(trip)?.color"
              variant="subtle"
              size="sm"
              class="shrink-0"
            />
            <UIcon
              name="i-lucide-chevron-right"
              class="size-5 shrink-0 text-dimmed"
            />
          </NuxtLink>
        </li>
      </ul>
      <p
        v-else
        class="text-sm text-muted"
      >
        Noch keine Fahrt geplant.
      </p>
    </section>

    <section class="space-y-2">
      <h4 class="text-xs font-semibold tracking-wide text-muted uppercase">
        Tickets
      </h4>
      <NuxtLink
        v-if="ticketRound"
        :to="`/clubs/${clubId}/tickets/${ticketRound.id}`"
        class="flex items-center gap-3 rounded-md border border-default px-3 py-2.5 transition-colors hover:bg-elevated/50"
      >
        <UIcon
          name="i-lucide-ticket"
          class="size-5 shrink-0 text-primary"
        />
        <span class="min-w-0 flex-1">
          <span class="block font-medium text-highlighted">Ticketabfrage</span>
          <span class="block text-sm text-muted">
            {{ ticketMeta }}<template v-if="isOrganizer && ticketRound.openCount"> · {{ ticketRound.openCount }} offen</template>
          </span>
          <span
            v-if="myTicketBadges.length"
            class="mt-1 flex flex-wrap gap-1"
          >
            <UBadge
              v-for="badge in myTicketBadges"
              :key="badge.label"
              :label="badge.label"
              :color="badge.color"
              variant="subtle"
              size="sm"
            />
          </span>
        </span>
        <UIcon
          name="i-lucide-chevron-right"
          class="size-5 shrink-0 text-dimmed"
        />
      </NuxtLink>
      <p
        v-else
        class="text-sm text-muted"
      >
        Noch keine Ticketabfrage.
      </p>
    </section>

    <div
      v-if="isOrganizer"
      class="grid gap-2"
      :class="ticketRound ? 'grid-cols-1' : 'grid-cols-2'"
    >
      <UButton
        :to="`/clubs/${clubId}/trips/new?match=${match.matchId}`"
        label="Fahrt planen"
        icon="i-lucide-plus"
        variant="soft"
        block
      />
      <UButton
        v-if="!ticketRound"
        :to="`/clubs/${clubId}/tickets/new?match=${match.matchId}`"
        label="Tickets abfragen"
        icon="i-lucide-ticket-plus"
        variant="soft"
        block
      />
    </div>
  </UCard>
</template>
