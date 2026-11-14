<script setup lang="ts">
import type { AccordionItem } from '@nuxt/ui'

useHead({ title: 'Meine Tickets' })

const { groups, error, refresh } = await useMyTickets()

const upcoming = computed(() => groups.value.filter(group => !group.past))
const past = computed(() => groups.value.filter(group => group.past))

const pastItems = computed<AccordionItem[]>(() => [{
  label: past.value.length === 1 ? '1 vergangenes Spiel' : `${past.value.length} vergangene Spiele`,
  icon: 'i-lucide-history'
}])
</script>

<template>
  <div class="space-y-6">
    <div class="space-y-1">
      <h1 class="text-2xl font-bold text-highlighted">
        Meine Tickets
      </h1>
      <p class="text-muted">
        Deine Ticketanfragen aus allen Fanclubs.
      </p>
    </div>

    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      icon="i-lucide-circle-alert"
      title="Deine Tickets konnten nicht geladen werden."
      description="Versuch es gleich noch einmal."
    />

    <UEmpty
      v-else-if="!groups.length"
      icon="i-lucide-ticket"
      title="Noch keine Tickets"
      description="Tickets fragst du in deinem Fanclub beim jeweiligen Spiel an."
      :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
    />

    <template v-else>
      <p
        v-if="!upcoming.length"
        class="text-sm text-muted"
      >
        Für kommende Spiele hast du keine Tickets angefragt.
      </p>

      <MyTicketGroupCard
        v-for="group in upcoming"
        :key="group.round.id"
        :group="group"
        @changed="refresh"
      />

      <UAccordion
        v-if="past.length"
        :items="pastItems"
        :ui="{ trigger: 'text-base', body: 'space-y-3' }"
      >
        <template #body>
          <MyTicketGroupCard
            v-for="group in past"
            :key="group.round.id"
            :group="group"
            @changed="refresh"
          />
        </template>
      </UAccordion>
    </template>
  </div>
</template>
