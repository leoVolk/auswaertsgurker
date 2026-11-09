<script setup lang="ts">
import type { AwayMatch } from '#shared/types/openligadb'
import type { TripSummary } from '~/composables/useTrips'

defineProps<{
  clubId: string
  match: AwayMatch
  trips: TripSummary[]
  isOrganizer: boolean
}>()
</script>

<template>
  <UCard :ui="{ body: 'space-y-4' }">
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
            <span class="block text-sm text-muted">
              {{ trip.departureAt ? `Abfahrt ${formatDateTime(trip.departureAt)}` : 'Abfahrt noch offen' }}
            </span>
          </span>
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

    <UButton
      v-if="isOrganizer"
      :to="`/clubs/${clubId}/trips/new?match=${match.matchId}`"
      label="Fahrt planen"
      icon="i-lucide-plus"
      variant="soft"
      block
    />
  </UCard>
</template>
