<script setup lang="ts">
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

const details = computed(() => {
  const t = trip.value
  if (!t) return []
  return [
    {
      icon: 'i-lucide-clock',
      label: 'Abfahrt',
      value: t.departureAt ? formatDateTime(t.departureAt) : 'Noch offen'
    },
    {
      icon: 'i-lucide-map-pin',
      label: 'Treffpunkt',
      value: t.meetingPoint ?? 'Noch offen'
    },
    {
      icon: 'i-lucide-users',
      label: 'Plätze',
      value: t.capacity ? `${t.capacity} Plätze` : 'Unbegrenzt'
    },
    {
      icon: 'i-lucide-euro',
      label: 'Kosten',
      value: t.priceCents != null ? `${formatPrice(t.priceCents)} pro Person` : 'Noch offen'
    },
    ...(t.registrationDeadline
      ? [{ icon: 'i-lucide-calendar-clock', label: 'Anmeldeschluss', value: formatDateTime(t.registrationDeadline) }]
      : [])
  ]
})

const deleteOpen = ref(false)

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
          :name="TRANSPORT_MODES[trip.transport].icon"
          class="size-7 shrink-0 text-primary"
        />
        <h1 class="text-2xl font-bold text-highlighted">
          {{ tripLabel(trip) }}
        </h1>
      </div>
      <div class="space-y-1 text-sm">
        <p class="font-medium text-highlighted">
          {{ trip.awayGame.matchday }}. Spieltag bei {{ trip.awayGame.opponentName }}
        </p>
        <KickoffLabel
          :kickoff-at="kickoffAt"
          :provisional-at="liveMatch?.provisionalAt"
        />
      </div>
    </div>

    <UCard :ui="{ body: 'p-0 sm:p-0' }">
      <dl class="divide-y divide-default">
        <div
          v-for="item in details"
          :key="item.label"
          class="flex items-start gap-3 px-4 py-3 sm:px-6"
        >
          <UIcon
            :name="item.icon"
            class="mt-0.5 size-5 shrink-0 text-dimmed"
          />
          <dt class="w-32 shrink-0 text-muted">
            {{ item.label }}
          </dt>
          <dd class="min-w-0 font-medium text-highlighted">
            {{ item.value }}
          </dd>
        </div>
        <div
          v-if="trip.notes"
          class="space-y-1 px-4 py-3 sm:px-6"
        >
          <dt class="flex items-center gap-3 text-muted">
            <UIcon
              name="i-lucide-info"
              class="size-5 shrink-0 text-dimmed"
            />
            Hinweise
          </dt>
          <dd class="whitespace-pre-line text-highlighted">
            {{ trip.notes }}
          </dd>
        </div>
      </dl>
    </UCard>

    <TripRegistrationCard
      :trip="trip"
      :stats="tripStats"
      :paypal-me="club.paypalMe"
      @changed="onRegistrationChanged"
    />

    <TripParticipants
      v-if="isOrganizer"
      :trip-id="trip.id"
      :capacity="trip.capacity"
      :price-cents="trip.priceCents"
      @changed="refreshStats"
    />

    <div
      v-if="isOrganizer"
      class="grid gap-2"
    >
      <UButton
        :to="`/clubs/${club.id}/trips/${trip.id}/edit`"
        label="Fahrt bearbeiten"
        icon="i-lucide-pencil"
        color="neutral"
        variant="outline"
        size="lg"
        block
      />

      <UModal
        v-model:open="deleteOpen"
        title="Fahrt löschen?"
        description="Die Fahrt wird samt aller Anmeldungen für alle Mitglieder entfernt. Das lässt sich nicht rückgängig machen."
      >
        <UButton
          label="Fahrt löschen"
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
  </div>
</template>
