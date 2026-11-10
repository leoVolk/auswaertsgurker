<script setup lang="ts">
import type { MyTicketGroup } from '~/composables/useTickets'

defineProps<{
  group: MyTicketGroup
}>()

const emit = defineEmits<{ changed: [] }>()
</script>

<template>
  <UCard :ui="{ body: 'space-y-4' }">
    <template #header>
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0 space-y-1">
          <p class="truncate text-sm text-muted">
            {{ group.club.name }} · {{ group.round.awayGame.matchday }}. Spieltag
          </p>
          <h2 class="text-lg font-semibold text-highlighted">
            bei {{ group.round.awayGame.opponentName }}
          </h2>
          <KickoffLabel
            :kickoff-at="group.round.awayGame.kickoffAt"
            class="text-sm"
          />
        </div>
        <UButton
          :to="`/clubs/${group.club.id}/tickets/${group.round.id}`"
          label="Abfrage"
          trailing-icon="i-lucide-chevron-right"
          color="neutral"
          variant="ghost"
          size="sm"
          class="-me-2 shrink-0"
        />
      </div>
    </template>

    <MyTicketRequests
      :requests="group.requests"
      :categories="group.round.categories"
      :membership-number-required="group.round.membershipNumberRequired"
      :download-requires-payment="group.round.downloadRequiresPayment"
      :purged="group.round.personalDataPurged"
      @changed="emit('changed')"
    />

    <MyTicketPayment
      :requests="group.requests"
      :categories="group.round.categories"
      :away-game="group.round.awayGame"
      :paypal-me="group.club.paypalMe"
      @changed="emit('changed')"
    />
  </UCard>
</template>
