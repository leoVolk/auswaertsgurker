<script setup lang="ts">
import type { DropdownMenuItem, TabsItem } from '@nuxt/ui'

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

// Organisatoren: Tabs „Übersicht“/„Verwaltung“, gemerkt in der URL (?tab=admin)
const tab = computed({
  get: () => (isOrganizer.value && route.query.tab === 'admin' ? 'admin' : 'overview'),
  set: value => navigateTo({ query: { ...route.query, tab: value === 'admin' ? 'admin' : undefined } }, { replace: true })
})
const openCount = computed(() => requests.value.filter(r => r.status === 'requested').length)
const tabItems = computed<TabsItem[]>(() => [
  { label: 'Übersicht', value: 'overview' },
  { label: 'Verwaltung', value: 'admin', badge: openCount.value || undefined }
])

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
const actions = computed<DropdownMenuItem[][]>(() => isOrganizer.value && round.value
  ? [
      [
        { label: 'Ticketabfrage bearbeiten', icon: 'i-lucide-pencil', to: `/clubs/${clubId.value}/tickets/${round.value.id}/edit` },
        {
          label: isOpen.value ? 'Ticketabfrage schließen' : 'Ticketabfrage wieder öffnen',
          icon: isOpen.value ? 'i-lucide-lock' : 'i-lucide-lock-open',
          onSelect: toggleClosed
        }
      ],
      [{ label: 'Ticketabfrage löschen', icon: 'i-lucide-trash-2', color: 'error', onSelect: () => { deleteOpen.value = true } }]
    ]
  : [])

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
    class="space-y-5"
  >
    <DetailHeader
      :back-to="`/clubs/${club.id}`"
      :back-label="club.name"
      icon="i-lucide-ticket"
      title="Tickets"
      :badge="isOpen ? { label: 'Offen', color: 'success' } : { label: 'Geschlossen', color: 'neutral' }"
      :matchday="round.awayGame.matchday"
      :opponent-name="round.awayGame.opponentName"
      :kickoff-at="kickoffAt"
      :provisional-at="liveMatch?.provisionalAt"
      :actions="actions"
    />

    <UTabs
      v-if="isOrganizer"
      v-model="tab"
      :items="tabItems"
      :content="false"
      variant="link"
      class="w-full"
    />

    <template v-if="tab === 'overview'">
      <!-- Eigene Anfragen zuerst: Status und Bezahlen sind der häufigste Grund für den Besuch -->
      <UCard
        v-if="myRequests.length"
        :ui="{ body: 'space-y-4' }"
      >
        <h2 class="font-semibold text-highlighted">
          Deine Anfragen
        </h2>
        <MyTicketRequests
          :requests="myRequests"
          :categories="round.categories"
          :membership-number-required="round.membershipNumberRequired"
          :download-requires-payment="round.downloadRequiresPayment"
          :purged="round.personalDataPurged"
          @changed="refreshRequests"
        />
        <MyTicketPayment
          :requests="myRequests"
          :categories="round.categories"
          :away-game="round.awayGame"
          :paypal-me="club.paypalMe"
          @changed="refreshRequests"
        />
      </UCard>

      <UCard :ui="{ body: 'space-y-4' }">
        <StatusLine
          v-if="round.personalDataPurged"
          color="neutral"
          title="Ticketdaten gelöscht"
          :description="`Mitgliedsnummern und Ticket-PDFs wurden ${TICKET_DATA_RETENTION_DAYS} Tage nach dem Spiel automatisch gelöscht.`"
        />

        <ul class="divide-y divide-default text-sm">
          <li
            v-for="category in round.categories"
            :key="category.id"
            class="flex items-center justify-between gap-3 py-2 first:pt-0 last:pb-0"
          >
            <span class="font-medium text-highlighted">{{ category.name }}</span>
            <span class="text-muted">
              {{ formatPrice(category.priceCents) }}<template v-if="category.quota !== null"> · {{ category.quota }} Tickets</template>
            </span>
          </li>
        </ul>

        <dl
          v-if="(isOpen && round.requestDeadline) || round.maxTicketsPerMember"
          class="grid grid-cols-2 gap-x-4 gap-y-3 border-t border-default pt-4 text-sm"
        >
          <div v-if="isOpen && round.requestDeadline">
            <dt class="text-muted">
              Anfragen bis
            </dt>
            <dd class="font-medium text-highlighted">
              {{ formatDateTime(round.requestDeadline) }}
            </dd>
          </div>
          <div v-if="round.maxTicketsPerMember">
            <dt class="text-muted">
              Pro Mitglied
            </dt>
            <dd class="font-medium text-highlighted">
              max. {{ round.maxTicketsPerMember }} Tickets
            </dd>
          </div>
        </dl>

        <p
          v-if="round.notes"
          class="border-t border-default pt-4 text-sm whitespace-pre-line text-default"
        >
          {{ round.notes }}
        </p>

        <p class="flex gap-2 text-xs text-muted">
          <UIcon
            name="i-lucide-scale"
            class="size-4 shrink-0"
          />
          Weitergabe nur zum Originalpreis, kein öffentlicher Weiterverkauf.
        </p>
      </UCard>

      <UCard
        v-if="isOpen"
        :ui="{ body: 'space-y-4' }"
      >
        <div class="space-y-0.5">
          <h2 class="font-semibold text-highlighted">
            Ticket anfragen
          </h2>
          <p
            v-if="remaining !== null && remaining > 0"
            class="text-sm text-muted"
          >
            Du kannst noch {{ remaining }} {{ remaining === 1 ? 'Ticket' : 'Tickets' }} anfragen.
          </p>
        </div>
        <StatusLine
          v-if="remaining !== null && remaining <= 0"
          color="info"
          :title="`Du hast bereits ${round.maxTicketsPerMember} Tickets angefragt.`"
          description="Storniere eine Anfrage, wenn du ein Ticket für jemand anderen anfragen möchtest."
        />
        <TicketRequestForm
          v-else
          :round="round"
          :default-holder-name="myRequests.length ? '' : profile?.display_name ?? ''"
          @requested="refreshRequests"
        />
      </UCard>
    </template>

    <TicketRequestsAdmin
      v-else
      :round="round"
      :requests="requests"
      @changed="refreshAll"
    />

    <UModal
      v-model:open="deleteOpen"
      title="Ticketabfrage löschen?"
      description="Alle Kategorien und Anfragen werden mit gelöscht. Das lässt sich nicht rückgängig machen."
    >
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
