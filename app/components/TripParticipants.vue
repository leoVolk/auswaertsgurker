<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { RegistrationStatus, TripParticipant } from '~/composables/useTripRegistrations'

const props = defineProps<{
  tripId: string
  capacity: number | null
}>()

const emit = defineEmits<{ changed: [] }>()

const { participants, refresh } = await useTripParticipants(() => props.tripId)
const { cancel, confirm, confirmAll } = useTripRegistrationActions()
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
    .map(group => ({ ...group, items: participants.value.filter(p => p.status === group.status) }))
    .filter(group => group.items.length > 0)
)

const requestedCount = computed(() => participants.value.filter(p => p.status === 'requested').length)
const takenCount = computed(() =>
  participants.value.filter(p => p.status === 'requested' || p.status === 'confirmed').length
)
const isOverbooked = computed(() => props.capacity !== null && takenCount.value > props.capacity)

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
    const count = await confirmAll(props.tripId)
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

function actions(participant: TripParticipant): DropdownMenuItem[][] {
  const cancelAction: DropdownMenuItem = {
    label: participant.status === 'waitlist' ? 'Von der Warteliste nehmen' : 'Platz freigeben',
    icon: 'i-lucide-user-minus',
    color: 'error',
    onSelect: () => {
      participantToCancel.value = participant
    }
  }

  if (participant.status === 'requested') {
    return [[{ label: 'Bestätigen', icon: 'i-lucide-check', onSelect: () => onConfirm(participant) }], [cancelAction]]
  }
  return [[cancelAction]]
}
</script>

<template>
  <UCard :ui="{ body: 'space-y-4' }">
    <template #header>
      <div class="flex items-center justify-between gap-3">
        <h2 class="font-semibold text-highlighted">
          Anmeldungen
        </h2>
        <UButton
          v-if="requestedCount > 0"
          :label="`Alle bestätigen (${requestedCount})`"
          icon="i-lucide-check-check"
          size="sm"
          loading-auto
          @click="onConfirmAll"
        />
      </div>
    </template>

    <UAlert
      v-if="isOverbooked"
      color="warning"
      variant="subtle"
      icon="i-lucide-triangle-alert"
      title="Mehr Plätze vergeben als vorhanden"
      description="Erhöhe die Platzzahl der Fahrt oder gib einzelne Plätze frei."
    />

    <p
      v-if="!groups.length"
      class="text-sm text-muted"
    >
      Noch keine Anmeldungen.
    </p>

    <section
      v-for="group in groups"
      :key="group.status"
      class="space-y-2"
    >
      <h3 class="flex items-center gap-2 text-sm font-medium text-muted">
        <UBadge
          :label="group.title"
          :color="REGISTRATION_STATUS[group.status].color"
          variant="subtle"
          size="sm"
        />
        {{ group.items.length }}
      </h3>

      <ul class="divide-y divide-default rounded-md border border-default">
        <li
          v-for="(participant, index) in group.items"
          :key="participant.id"
          class="flex items-center justify-between gap-3 px-3 py-2"
          :class="{ 'opacity-60': group.status === 'cancelled' }"
        >
          <UUser
            :name="group.status === 'waitlist' ? `${index + 1}. ${participant.displayName}` : participant.displayName"
            :avatar="{ alt: participant.displayName }"
            size="sm"
          />

          <UDropdownMenu
            v-if="group.status !== 'cancelled'"
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
    </section>

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
  </UCard>
</template>
