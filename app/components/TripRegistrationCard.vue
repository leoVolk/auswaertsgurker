<script setup lang="ts">
import type { TripStats } from '~/composables/useTripRegistrations'
import type { TripDetail } from '~/composables/useTrips'

const props = defineProps<{
  trip: TripDetail
  stats?: TripStats
}>()

const emit = defineEmits<{ changed: [] }>()

const { register, cancel } = useTripRegistrationActions()
const toast = useToast()
const showError = useErrorToast()

const status = computed(() => props.stats?.myStatus ?? null)
const isActive = computed(() => status.value !== null && status.value !== 'cancelled')
const isFull = computed(() =>
  props.trip.capacity !== null && (props.stats?.takenSeats ?? 0) >= props.trip.capacity
)
const closedReason = computed(() => registrationClosedReason(props.trip))

async function onRegister() {
  try {
    const result = await register(props.trip.id)
    toast.add(result === 'waitlist'
      ? {
          title: 'Du stehst auf der Warteliste',
          description: 'Wird ein Platz frei, rückst du automatisch nach.',
          color: 'info',
          icon: 'i-lucide-list-ordered'
        }
      : {
          title: 'Du bist angemeldet',
          description: 'Ein Organisator bestätigt deinen Platz.',
          color: 'success',
          icon: 'i-lucide-check'
        })
    emit('changed')
  } catch (error) {
    showError(error)
  }
}

const cancelOpen = ref(false)

async function onCancel() {
  const registrationId = props.stats?.myRegistrationId
  if (!registrationId) return
  try {
    await cancel(registrationId)
    cancelOpen.value = false
    toast.add({ title: 'Du hast abgesagt', color: 'success', icon: 'i-lucide-check' })
    emit('changed')
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UCard
    title="Deine Anmeldung"
    :ui="{ body: 'space-y-4' }"
  >
    <TripSeats
      :capacity="trip.capacity"
      :stats="stats"
    />

    <UAlert
      v-if="status === 'confirmed'"
      color="success"
      variant="subtle"
      icon="i-lucide-circle-check"
      title="Dein Platz ist bestätigt."
    />
    <UAlert
      v-else-if="status === 'requested'"
      color="warning"
      variant="subtle"
      icon="i-lucide-hourglass"
      title="Du bist angemeldet."
      description="Ein Organisator bestätigt deinen Platz noch."
    />
    <UAlert
      v-else-if="status === 'waitlist'"
      color="info"
      variant="subtle"
      icon="i-lucide-list-ordered"
      :title="`Du stehst auf Platz ${stats?.myWaitlistPosition ?? '?'} der Warteliste.`"
      description="Wird ein Platz frei, rückst du automatisch nach."
    />

    <template v-if="!isActive">
      <p
        v-if="status === 'cancelled'"
        class="text-sm text-muted"
      >
        Du hast für diese Fahrt abgesagt.
      </p>

      <UAlert
        v-if="closedReason"
        color="neutral"
        variant="subtle"
        icon="i-lucide-lock"
        :title="closedReason"
      />
      <template v-else>
        <p
          v-if="isFull"
          class="text-sm text-muted"
        >
          Die Fahrt ist voll. Auf der Warteliste rückst du automatisch nach, sobald jemand absagt.
        </p>
        <UButton
          :label="isFull ? 'Auf die Warteliste' : 'Mitfahren'"
          :icon="isFull ? 'i-lucide-list-plus' : 'i-lucide-user-plus'"
          :color="isFull ? 'neutral' : 'primary'"
          :variant="isFull ? 'outline' : 'solid'"
          size="lg"
          block
          loading-auto
          @click="onRegister"
        />
      </template>
    </template>

    <UModal
      v-else
      v-model:open="cancelOpen"
      :title="status === 'waitlist' ? 'Von der Warteliste nehmen?' : 'Wirklich absagen?'"
      :description="status === 'waitlist'
        ? 'Du verlierst deinen Platz auf der Warteliste.'
        : 'Dein Platz wird freigegeben und die nächste Person auf der Warteliste rückt nach.'"
    >
      <UButton
        :label="status === 'waitlist' ? 'Von der Warteliste nehmen' : 'Absagen'"
        icon="i-lucide-user-minus"
        color="neutral"
        variant="outline"
        size="lg"
        block
      />

      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            label="Doch nicht"
            color="neutral"
            variant="ghost"
            @click="cancelOpen = false"
          />
          <UButton
            label="Absagen"
            color="error"
            loading-auto
            @click="onCancel"
          />
        </div>
      </template>
    </UModal>
  </UCard>
</template>
