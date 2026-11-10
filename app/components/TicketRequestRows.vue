<script setup lang="ts">
import type { BadgeProps, DropdownMenuItem } from '@nuxt/ui'
import type { TicketRequest } from '~/composables/useTickets'

// Zeilen der Organisator-Ansicht; Darstellung und Aktionen kommen aus TicketRequestsAdmin
defineProps<{
  requests: TicketRequest[]
  dimmed?: boolean
  deliveryLine: (request: TicketRequest) => { icon: string, text: string, class: string } | null
  paymentBadge: (request: TicketRequest) => { label: string, color: BadgeProps['color'] } | null
  actions: (request: TicketRequest) => DropdownMenuItem[][]
}>()
</script>

<template>
  <ul class="divide-y divide-default rounded-md border border-default">
    <li
      v-for="request in requests"
      :key="request.id"
      class="flex items-center gap-3 px-3 py-2"
      :class="{ 'opacity-60': dimmed && request.paymentStatus !== 'confirmed' }"
    >
      <span class="min-w-0 flex-1">
        <span class="block truncate font-medium text-highlighted">{{ request.holderName }}</span>
        <span class="block truncate text-sm text-muted">
          <template v-if="request.requesterName !== request.holderName">über {{ request.requesterName }}</template>
          <template v-if="request.requesterName !== request.holderName && request.holderMembershipNumber"> · </template>
          <template v-if="request.holderMembershipNumber">Nr. {{ request.holderMembershipNumber }}</template>
        </span>
        <span
          v-if="deliveryLine(request)"
          class="flex items-center gap-1.5 text-sm"
          :class="deliveryLine(request)?.class"
        >
          <UIcon
            :name="deliveryLine(request)?.icon ?? ''"
            class="size-4 shrink-0"
          />
          <span class="truncate">{{ deliveryLine(request)?.text }}</span>
        </span>
      </span>
      <!-- Zahlung rechts wie in der Mitgliederansicht, damit die Zeile nicht höher wird -->
      <UBadge
        v-if="paymentBadge(request)"
        :label="paymentBadge(request)?.label"
        :color="paymentBadge(request)?.color"
        variant="solid"
        size="sm"
        class="shrink-0"
      />
      <UDropdownMenu
        v-if="actions(request).length"
        :items="actions(request)"
        :content="{ align: 'end' }"
      >
        <UButton
          icon="i-lucide-ellipsis-vertical"
          color="neutral"
          variant="ghost"
          :aria-label="`Aktionen für ${request.holderName}`"
        />
      </UDropdownMenu>
    </li>
  </ul>
</template>
