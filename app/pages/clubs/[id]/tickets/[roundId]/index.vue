<script setup lang="ts">
const route = useRoute()
const clubId = computed(() => String(route.params.id))
const roundId = computed(() => String(route.params.roundId))
const userId = useCurrentUserId()
const { profile } = useProfile()
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer } = await useClub(clubId)
const { round: loadedRound, refresh: refreshRound } = await useTicketRound(roundId)
const { requests, refresh: refreshRequests } = await useTicketRequests(roundId)
const { matches } = await useAwayMatches(() => club.value?.team)
const { setClosed, deleteRound } = useTicketRoundActions(clubId)

// Abfrage nur im passenden Fanclub anzeigen
const round = computed(() => (loadedRound.value?.clubId === clubId.value ? loadedRound.value : null))

const liveMatch = computed(() => matches.value.find(m => m.matchId === round.value?.awayGame.matchId))
const kickoffAt = computed(() => (liveMatch.value ? liveMatch.value.kickoffAt : round.value?.awayGame.kickoffAt ?? null))

const isOpen = computed(() => (round.value ? isTicketRoundOpen(round.value) : false))
const myRequests = computed(() => requests.value.filter(r => r.requestedBy === userId.value))
const myActiveCount = computed(() => myRequests.value.filter(r => ACTIVE_TICKET_STATUSES.includes(r.status)).length)
const remaining = computed(() =>
  round.value?.maxTicketsPerMember != null ? round.value.maxTicketsPerMember - myActiveCount.value : null
)

useHead({ title: () => (round.value ? `Tickets bei ${round.value.awayGame.opponentName}` : 'Tickets') })

async function refreshAll() {
  await Promise.all([refreshRound(), refreshRequests()])
}

async function toggleClosed() {
  if (!round.value) return
  const closing = isOpen.value
  try {
    await setClosed(round.value.id, closing)
    await refreshRound()
    toast.add({
      title: closing ? 'Ticketabfrage geschlossen' : 'Ticketabfrage wieder geöffnet',
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  }
}

const deleteOpen = ref(false)

async function onDelete() {
  if (!round.value) return
  try {
    await deleteRound(round.value.id)
    deleteOpen.value = false
    toast.add({ title: 'Ticketabfrage gelöscht', color: 'success', icon: 'i-lucide-check' })
    await navigateTo(`/clubs/${clubId.value}`, { replace: true })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UEmpty
    v-if="!club || !round"
    icon="i-lucide-search-x"
    title="Ticketabfrage nicht gefunden"
    description="Die Abfrage wurde gelöscht oder du bist kein Mitglied dieses Fanclubs."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <div class="space-y-2">
      <UButton
        :to="`/clubs/${club.id}`"
        :label="`Zurück zu ${club.name}`"
        icon="i-lucide-arrow-left"
        color="neutral"
        variant="link"
        class="-ms-2.5 max-w-full"
        :ui="{ label: 'truncate' }"
      />
      <div class="flex items-center gap-3">
        <UIcon
          name="i-lucide-ticket"
          class="size-7 shrink-0 text-primary"
        />
        <h1 class="text-2xl font-bold text-highlighted">
          Tickets
        </h1>
        <UBadge
          :label="isOpen ? 'Offen' : 'Geschlossen'"
          :color="isOpen ? 'success' : 'neutral'"
          variant="subtle"
        />
      </div>
      <div class="space-y-1 text-sm">
        <p class="font-medium text-highlighted">
          {{ round.awayGame.matchday }}. Spieltag bei {{ round.awayGame.opponentName }}
        </p>
        <KickoffLabel
          :kickoff-at="kickoffAt"
          :provisional-at="liveMatch?.provisionalAt"
        />
      </div>
    </div>

    <UCard :ui="{ body: 'space-y-4' }">
      <dl class="space-y-2 text-sm">
        <div class="flex gap-3">
          <dt class="w-36 shrink-0 text-muted">
            Anfragen bis
          </dt>
          <dd class="font-medium text-highlighted">
            {{ round.closedAt ? 'Geschlossen' : round.requestDeadline ? formatDateTime(round.requestDeadline) : 'Keine Frist' }}
          </dd>
        </div>
        <div
          v-if="round.maxTicketsPerMember"
          class="flex gap-3"
        >
          <dt class="w-36 shrink-0 text-muted">
            Pro Mitglied
          </dt>
          <dd class="font-medium text-highlighted">
            höchstens {{ round.maxTicketsPerMember }} Tickets
          </dd>
        </div>
      </dl>

      <ul class="divide-y divide-default rounded-md border border-default">
        <li
          v-for="category in round.categories"
          :key="category.id"
          class="flex items-center justify-between gap-3 px-3 py-2 text-sm"
        >
          <span class="font-medium text-highlighted">{{ category.name }}</span>
          <span class="text-muted">
            {{ formatPrice(category.priceCents) }}<template v-if="category.quota !== null"> · {{ category.quota }} Tickets</template>
          </span>
        </li>
      </ul>

      <p
        v-if="round.notes"
        class="whitespace-pre-line text-sm text-highlighted"
      >
        {{ round.notes }}
      </p>

      <UAlert
        color="neutral"
        variant="subtle"
        icon="i-lucide-scale"
        title="Weitergabe nur zum Originalpreis"
        description="Tickets aus dem Fanclub-Kontingent dürfen nicht öffentlich weiterverkauft werden."
      />
    </UCard>

    <UCard
      title="Ticket anfragen"
      :ui="{ body: 'space-y-4' }"
    >
      <UAlert
        v-if="!isOpen"
        color="neutral"
        variant="subtle"
        icon="i-lucide-lock"
        title="Die Ticketabfrage ist geschlossen."
      />
      <UAlert
        v-else-if="remaining !== null && remaining <= 0"
        color="info"
        variant="subtle"
        icon="i-lucide-info"
        :title="`Du hast bereits ${round.maxTicketsPerMember} Tickets angefragt.`"
        description="Storniere eine Anfrage, wenn du ein Ticket für jemand anderen anfragen möchtest."
      />
      <template v-else>
        <p
          v-if="remaining !== null"
          class="text-sm text-muted"
        >
          Du kannst noch {{ remaining }} {{ remaining === 1 ? 'Ticket' : 'Tickets' }} anfragen.
        </p>
        <TicketRequestForm
          :round="round"
          :default-holder-name="myRequests.length ? '' : profile?.display_name ?? ''"
          @requested="refreshRequests"
        />
      </template>
    </UCard>

    <UCard
      v-if="myRequests.length"
      title="Deine Anfragen"
    >
      <MyTicketRequests
        :requests="myRequests"
        :categories="round.categories"
        :membership-number-required="round.membershipNumberRequired"
        @changed="refreshRequests"
      />
    </UCard>

    <template v-if="isOrganizer">
      <TicketRequestsAdmin
        :round="round"
        :requests="requests"
        @changed="refreshAll"
      />

      <div class="grid gap-2">
        <UButton
          :to="`/clubs/${club.id}/tickets/${round.id}/edit`"
          label="Ticketabfrage bearbeiten"
          icon="i-lucide-pencil"
          color="neutral"
          variant="outline"
          size="lg"
          block
        />
        <UButton
          :label="isOpen ? 'Ticketabfrage schließen' : 'Ticketabfrage wieder öffnen'"
          :icon="isOpen ? 'i-lucide-lock' : 'i-lucide-lock-open'"
          color="neutral"
          variant="outline"
          size="lg"
          block
          loading-auto
          @click="toggleClosed"
        />

        <UModal
          v-model:open="deleteOpen"
          title="Ticketabfrage löschen?"
          description="Die Abfrage wird samt aller Kategorien und Anfragen entfernt. Das lässt sich nicht rückgängig machen."
        >
          <UButton
            label="Ticketabfrage löschen"
            icon="i-lucide-trash-2"
            color="error"
            variant="ghost"
            size="lg"
            block
          />

          <template #footer>
            <div class="flex w-full justify-end gap-2">
              <UButton
                label="Abbrechen"
                color="neutral"
                variant="ghost"
                @click="deleteOpen = false"
              />
              <UButton
                label="Löschen"
                color="error"
                loading-auto
                @click="onDelete"
              />
            </div>
          </template>
        </UModal>
      </div>
    </template>
  </div>
</template>
