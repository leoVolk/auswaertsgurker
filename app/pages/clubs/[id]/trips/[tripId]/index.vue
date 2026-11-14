<script setup lang="ts">
import type { DropdownMenuItem, TabsItem } from '@nuxt/ui'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const tripId = computed(() => String(route.params.tripId))
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer } = await useClub(clubId)
const { trip: loadedTrip } = await useTrip(tripId)
const { matches } = await useAwayMatches(() => club.value?.team)
const { stats, refresh: refreshStats } = await useTripStats(clubId)
const { deleteTrip } = useTripActions(clubId)

// Fahrt nur im passenden Fanclub anzeigen
const trip = computed(() => (loadedTrip.value?.clubId === clubId.value ? loadedTrip.value : null))
const tripStats = computed(() => (trip.value ? stats.value.get(trip.value.id) : undefined))

async function onRegistrationChanged() {
  await Promise.all([
    refreshStats(),
    // Organisatoren sehen die eigene Anmeldung auch in der Liste
    isOrganizer.value ? refreshNuxtData(`trip-participants-${tripId.value}`) : undefined
  ])
}

// Anstoß möglichst aktuell aus OpenLigaDB, sonst der gespeicherte Stand
const liveMatch = computed(() => matches.value.find(m => m.matchId === trip.value?.awayGame.matchId))
const kickoffAt = computed(() => (liveMatch.value ? liveMatch.value.kickoffAt : trip.value?.awayGame.kickoffAt ?? null))

useHead({ title: () => (trip.value ? tripLabel(trip.value) : 'Fahrt') })

// Eckdaten kompakt; Plätze zeigt die Anmeldekarte mit Belegung
const details = computed(() => {
  const t = trip.value
  if (!t) return []
  return [
    { label: 'Abfahrt', value: t.departureAt ? formatDateTime(t.departureAt) : 'Noch offen' },
    { label: 'Treffpunkt', value: t.meetingPoint ?? 'Noch offen' },
    { label: 'Kosten', value: t.priceCents != null ? `${formatPrice(t.priceCents)} p. P.` : 'Noch offen' },
    ...(t.registrationDeadline ? [{ label: 'Anmeldeschluss', value: formatDateTime(t.registrationDeadline) }] : [])
  ]
})

// Organisatoren: Tabs „Übersicht“/„Verwaltung“, gemerkt in der URL (?tab=admin)
const tab = computed({
  get: () => (isOrganizer.value && route.query.tab === 'admin' ? 'admin' : 'overview'),
  set: value => navigateTo({ query: { ...route.query, tab: value === 'admin' ? 'admin' : undefined } }, { replace: true })
})
const tabItems: TabsItem[] = [
  { label: 'Übersicht', value: 'overview' },
  { label: 'Verwaltung', value: 'admin' }
]

const deleteOpen = ref(false)
const actions = computed<DropdownMenuItem[][]>(() => isOrganizer.value && trip.value
  ? [
      [{ label: 'Fahrt bearbeiten', icon: 'i-lucide-pencil', to: `/clubs/${clubId.value}/trips/${trip.value.id}/edit` }],
      [{ label: 'Fahrt löschen', icon: 'i-lucide-trash-2', color: 'error', onSelect: () => { deleteOpen.value = true } }]
    ]
  : [])

async function onDelete() {
  if (!trip.value) return
  try {
    await deleteTrip(trip.value.id)
    deleteOpen.value = false
    toast.add({ title: 'Fahrt gelöscht', color: 'success', icon: 'i-lucide-check' })
    await navigateTo(`/clubs/${clubId.value}`, { replace: true })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UEmpty
    v-if="!club || !trip"
    icon="i-lucide-search-x"
    title="Fahrt nicht gefunden"
    description="Die Fahrt wurde gelöscht oder du bist kein Mitglied dieses Fanclubs."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-5"
  >
    <DetailHeader
      :back-to="`/clubs/${club.id}`"
      :back-label="club.name"
      :icon="TRANSPORT_MODES[trip.transport].icon"
      :title="tripLabel(trip)"
      :matchday="trip.awayGame.matchday"
      :opponent-name="trip.awayGame.opponentName"
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
      <UCard>
        <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <div
            v-for="item in details"
            :key="item.label"
            class="min-w-0"
          >
            <dt class="text-muted">
              {{ item.label }}
            </dt>
            <dd class="font-medium text-highlighted">
              {{ item.value }}
            </dd>
          </div>
        </dl>
        <p
          v-if="trip.notes"
          class="mt-4 border-t border-default pt-4 text-sm whitespace-pre-line text-default"
        >
          {{ trip.notes }}
        </p>
      </UCard>

      <TripRegistrationCard
        :trip="trip"
        :stats="tripStats"
        :paypal-me="club.paypalMe"
        @changed="onRegistrationChanged"
      />
    </template>

    <TripParticipants
      v-else
      :trip-id="trip.id"
      :capacity="trip.capacity"
      :price-cents="trip.priceCents"
      @changed="refreshStats"
    />

    <UModal
      v-model:open="deleteOpen"
      title="Fahrt löschen?"
      description="Alle Anmeldungen werden mit gelöscht. Das lässt sich nicht rückgängig machen."
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
