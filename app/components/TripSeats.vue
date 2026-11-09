<script setup lang="ts">
import type { TripStats } from '~/composables/useTripRegistrations'

const props = defineProps<{
  capacity: number | null
  stats?: TripStats
}>()

const taken = computed(() => props.stats?.takenSeats ?? 0)
const waitlist = computed(() => props.stats?.waitlistCount ?? 0)
</script>

<template>
  <div class="space-y-2">
    <div class="flex items-baseline justify-between gap-3 text-sm">
      <span class="font-medium text-highlighted">
        <template v-if="capacity">{{ taken }} von {{ capacity }} Plätzen vergeben</template>
        <template v-else>{{ taken }} {{ taken === 1 ? 'Anmeldung' : 'Anmeldungen' }}</template>
      </span>
      <span
        v-if="waitlist"
        class="shrink-0 text-muted"
      >
        {{ waitlist }} auf der Warteliste
      </span>
    </div>
    <UProgress
      v-if="capacity"
      :model-value="Math.min(taken, capacity)"
      :max="capacity"
      :color="taken >= capacity ? 'warning' : 'primary'"
      size="sm"
      :get-value-label="(value: number | null | undefined, max: number) => `${value ?? 0} von ${max} Plätzen vergeben`"
    />
  </div>
</template>
