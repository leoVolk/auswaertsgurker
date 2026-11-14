<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { PaymentStatus } from '~/composables/usePayments'
import type { RegistrationStatus, TripParticipant } from '~/composables/useTripRegistrations'
import type { TripDetail } from '~/composables/useTrips'
import type { ExportList } from '~/utils/exportList'

const props = defineProps<{
  trip: TripDetail
  clubName: string
}>()

const emit = defineEmits<{ changed: [] }>()

const { participants, refresh } = await useTripParticipants(() => props.trip.id)
const { cancel, confirm, confirmAll } = useTripRegistrationActions()
const { setPaymentStatus } = usePaymentActions()

const hasPrice = computed(() => (props.trip.priceCents ?? 0) > 0)
const isSeated = (p: TripParticipant) => p.status === 'requested' || p.status === 'confirmed'

// Zahlungsstand der Personen mit Platz
const payment = computed(() => {
  const seated = participants.value.filter(isSeated)
  const count = (status: PaymentStatus) => seated.filter(p => p.paymentStatus === status).length
  return {
    confirmed: count('confirmed'),
    reported: count('reported'),
    open: count('open'),
    reportedIds: seated.filter(p => p.paymentStatus === 'reported').map(p => p.id)
  }
})

/** Badge zur Zahlung; bei Abgesagten mit bestätigter Zahlung ein Hinweis zur Erstattung */
function paymentBadge(participant: TripParticipant) {
  if (!isSeated(participant)) {
    return participant.paymentStatus === 'confirmed'
      ? { label: 'Erstattung offen', color: 'warning' as const }
      : null
  }
  return hasPrice.value ? PAYMENT_STATUS[participant.paymentStatus] : null
}

async function onSetPayment(participant: TripParticipant, status: Exclude<PaymentStatus, 'reported'>) {
  try {
    await setPaymentStatus(status, { tripRegistrationIds: [participant.id] })
    await afterChange()
  } catch (error) {
    showError(error)
  }
}

async function onConfirmReported() {
  try {
    const count = await setPaymentStatus('confirmed', { tripRegistrationIds: payment.value.reportedIds })
    await afterChange()
    toast.add({
      title: count === 1 ? '1 Zahlung bestätigt' : `${count} Zahlungen bestätigt`,
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  }
}
const toast = useToast()
const showError = useErrorToast()

const GROUP_ORDER: { status: RegistrationStatus, title: string }[] = [
  { status: 'requested', title: 'Angefragt' },
  { status: 'confirmed', title: 'Bestätigt' },
  { status: 'waitlist', title: 'Warteliste' },
  { status: 'cancelled', title: 'Abgesagt' }
]

const groups = computed(() =>
  GROUP_ORDER
    .map((group) => {
      const items = participants.value.filter(p => p.status === group.status)
      // Bezahlt, aber ohne Platz (Warteliste, abgesagt): Organisatoren müssen erstatten
      const seated = group.status === 'requested' || group.status === 'confirmed'
      return { ...group, items, refundsOpen: seated ? 0 : items.filter(p => p.paymentStatus === 'confirmed').length }
    })
    .filter(group => group.items.length > 0)
)

const requestedCount = computed(() => participants.value.filter(p => p.status === 'requested').length)
const takenCount = computed(() =>
  participants.value.filter(p => p.status === 'requested' || p.status === 'confirmed').length
)
const isOverbooked = computed(() => props.trip.capacity !== null && takenCount.value > props.trip.capacity)

async function afterChange() {
  await refresh()
  emit('changed')
}

async function onConfirm(participant: TripParticipant) {
  try {
    await confirm(participant.id)
    await afterChange()
    toast.add({ title: `Platz für ${participant.displayName} bestätigt`, color: 'success', icon: 'i-lucide-check' })
  } catch (error) {
    showError(error)
  }
}

async function onConfirmAll() {
  try {
    const count = await confirmAll(props.trip.id)
    await afterChange()
    toast.add({
      title: count === 1 ? '1 Platz bestätigt' : `${count} Plätze bestätigt`,
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  }
}

const participantToCancel = ref<TripParticipant | null>(null)
const cancelOpen = computed({
  get: () => participantToCancel.value !== null,
  set: (open) => {
    if (!open) participantToCancel.value = null
  }
})

async function onCancelConfirmed() {
  const participant = participantToCancel.value
  if (!participant) return
  try {
    await cancel(participant.id)
    participantToCancel.value = null
    await afterChange()
    toast.add({ title: `${participant.displayName} wurde abgemeldet`, color: 'success', icon: 'i-lucide-check' })
  } catch (error) {
    showError(error)
  }
}

// Export der Anmeldeliste (ohne Abgesagte), Reihenfolge wie in den Gruppen
function participantExportList(): ExportList<TripParticipant & { position: number | null }> {
  const rows = groups.value
    .filter(group => group.status !== 'cancelled')
    .flatMap(group => group.items.map((participant, index) => ({
      ...participant,
      position: group.status === 'waitlist' ? index + 1 : null
    })))
  const label = tripLabel(props.trip)
  const game = `${props.trip.awayGame.matchday}. Spieltag bei ${props.trip.awayGame.opponentName}`

  return {
    title: `${label}: Anmeldungen`,
    subtitle: `${props.clubName} · ${game}`,
    fileName: exportFileName('anmeldungen', label, props.trip.awayGame.matchday, 'spieltag', props.trip.awayGame.opponentName),
    rows,
    columns: [
      { header: 'Name', value: p => p.displayName, width: 24 },
      { header: 'Status', value: p => (p.position ? `${REGISTRATION_STATUS[p.status].label} (${p.position}.)` : REGISTRATION_STATUS[p.status].label), width: 16 },
      ...(hasPrice.value ? [{ header: 'Zahlung', value: (p: TripParticipant) => paymentBadge(p)?.label, width: 16 }] : [])
    ]
  }
}
const exportItems = computed(() => exportMenuItems(participantExportList, error => showError(error, 'Der Export hat nicht geklappt.')))

function actions(participant: TripParticipant): DropdownMenuItem[][] {
  const cancelAction: DropdownMenuItem = {
    label: participant.status === 'waitlist' ? 'Von der Warteliste nehmen' : 'Platz freigeben',
    icon: 'i-lucide-user-minus',
    color: 'error',
    onSelect: () => {
      participantToCancel.value = participant
    }
  }

  const paymentItems = hasPrice.value || participant.paymentStatus !== 'open'
    ? paymentMenuItems(participant.paymentStatus, status => onSetPayment(participant, status))
    : []

  if (participant.status === 'cancelled') {
    return paymentItems.length ? [paymentItems] : []
  }
  if (participant.status === 'requested') {
    return [[{ label: 'Bestätigen', icon: 'i-lucide-check', onSelect: () => onConfirm(participant) }], paymentItems, [cancelAction]]
  }
  return [paymentItems, [cancelAction]]
}
</script>

<template>
  <section class="space-y-6">
    <div class="space-y-3">
      <div class="flex items-center gap-3">
        <p
          v-if="hasPrice && (payment.confirmed || payment.reported || payment.open)"
          class="text-sm text-muted"
        >
          Bezahlt {{ payment.confirmed }} · Gemeldet {{ payment.reported }} · Offen {{ payment.open }}
        </p>
        <UDropdownMenu
          v-if="participants.length"
          :items="exportItems"
          :content="{ align: 'end' }"
        >
          <UButton
            label="Liste"
            icon="i-lucide-download"
            color="neutral"
            variant="outline"
            size="sm"
            class="ms-auto shrink-0"
          />
        </UDropdownMenu>
      </div>
      <UButton
        v-if="requestedCount > 0"
        :label="`Alle Plätze bestätigen (${requestedCount})`"
        icon="i-lucide-check-check"
        block
        loading-auto
        @click="onConfirmAll"
      />
      <UButton
        v-if="payment.reported"
        :label="`Gemeldete Zahlungen bestätigen (${payment.reported})`"
        icon="i-lucide-badge-check"
        variant="soft"
        block
        loading-auto
        @click="onConfirmReported"
      />
      <UAlert
        v-if="isOverbooked"
        color="warning"
        variant="subtle"
        icon="i-lucide-triangle-alert"
        title="Mehr Plätze vergeben als vorhanden"
        description="Erhöhe die Platzzahl der Fahrt oder gib einzelne Plätze frei."
      />
    </div>

    <p
      v-if="!groups.length"
      class="text-sm text-muted"
    >
      Noch keine Anmeldungen.
    </p>

    <div
      v-else
      class="space-y-1"
    >
      <UCollapsible
        v-for="group in groups"
        :key="group.status"
        :default-open="group.status === 'requested'"
        class="flex flex-col gap-2"
      >
        <UButton
          color="neutral"
          variant="ghost"
          trailing-icon="i-lucide-chevron-down"
          block
          class="group justify-between px-0 hover:bg-transparent active:bg-transparent"
          :ui="{ trailingIcon: 'transition-transform duration-200 group-data-[state=open]:rotate-180' }"
        >
          <span class="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-sm">
            <UChip
              standalone
              inset
              :color="REGISTRATION_STATUS[group.status].color"
            />
            <span class="font-medium text-highlighted">
              {{ group.title }} ({{ group.items.length }})
            </span>
            <span
              v-if="group.refundsOpen"
              class="text-warning"
            >
              {{ group.refundsOpen === 1 ? '1 Erstattung offen' : `${group.refundsOpen} Erstattungen offen` }}
            </span>
          </span>
        </UButton>

        <template #content>
          <ul class="divide-y divide-default rounded-md border border-default">
            <li
              v-for="(participant, index) in group.items"
              :key="participant.id"
              class="flex items-center gap-3 px-3 py-2"
              :class="{ 'opacity-60': group.status === 'cancelled' && participant.paymentStatus !== 'confirmed' }"
            >
              <span class="min-w-0 flex-1 truncate font-medium text-highlighted">
                <template v-if="group.status === 'waitlist'">{{ index + 1 }}. </template>{{ participant.displayName }}
              </span>

              <UBadge
                v-if="paymentBadge(participant)"
                :label="paymentBadge(participant)?.label"
                :color="paymentBadge(participant)?.color"
                variant="solid"
                size="sm"
                class="shrink-0"
              />

              <UDropdownMenu
                v-if="actions(participant).length"
                :items="actions(participant)"
                :content="{ align: 'end' }"
              >
                <UButton
                  icon="i-lucide-ellipsis-vertical"
                  color="neutral"
                  variant="ghost"
                  :aria-label="`Aktionen für ${participant.displayName}`"
                />
              </UDropdownMenu>
            </li>
          </ul>
        </template>
      </UCollapsible>
    </div>

    <UModal
      v-model:open="cancelOpen"
      :title="participantToCancel?.status === 'waitlist' ? 'Von der Warteliste nehmen?' : 'Platz freigeben?'"
      :description="participantToCancel
        ? participantToCancel.status === 'waitlist'
          ? `${participantToCancel.displayName} wird von der Warteliste genommen.`
          : `${participantToCancel.displayName} wird abgemeldet. Die nächste Person auf der Warteliste rückt nach.`
        : undefined"
    >
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            label="Abbrechen"
            color="neutral"
            variant="ghost"
            @click="cancelOpen = false"
          />
          <UButton
            label="Abmelden"
            color="error"
            loading-auto
            @click="onCancelConfirmed"
          />
        </div>
      </template>
    </UModal>
  </section>
</template>
