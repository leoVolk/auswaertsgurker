<script setup lang="ts">
import type { FormSubmitEvent, RadioGroupItem } from '@nuxt/ui'
import type { TicketDeliveryMethod, TicketRequest } from '~/composables/useTickets'

const props = defineProps<{
  clubId: string
  /** Zugeteilte Tickets, für die die Hinterlegung gesetzt wird */
  requests: TicketRequest[]
}>()

const emit = defineEmits<{ saved: [] }>()
const open = defineModel<boolean>('open', { required: true })

const { setDelivery } = useTicketDeliveryActions(() => props.clubId)
const toast = useToast()
const showError = useErrorToast()

const methodItems = [
  { value: 'digital', label: 'PDF', description: 'Du lädst die Tickets hier hoch, Mitglieder laden sie herunter.' },
  { value: 'pickup', label: 'Abholung', description: 'Mitglieder holen die Tickets an einem Ort ab, z. B. am Bus.' },
  { value: 'box_office', label: 'Gästekasse', description: 'Die Tickets liegen auf den Namen des Inhabers an der Gästekasse.' }
] satisfies RadioGroupItem[]

const state = reactive({
  method: 'digital' as TicketDeliveryMethod,
  pickupLocation: '',
  pickupAt: ''
})

// Beim Öffnen mit der bisherigen Hinterlegung des ersten Tickets vorbelegen
watch(open, (isOpen) => {
  if (!isOpen) return
  const first = props.requests[0]
  state.method = first?.deliveryMethod ?? 'digital'
  state.pickupLocation = first?.pickupLocation ?? ''
  state.pickupAt = toBerlinInput(first?.pickupAt)
}, { immediate: true })

const filesToRemove = computed(() =>
  state.method === 'digital' ? 0 : props.requests.filter(r => r.ticketFilePath).length
)

async function onSubmit(event: FormSubmitEvent<TicketDeliveryForm>) {
  try {
    await setDelivery(
      props.requests.map(r => r.id),
      event.data.method,
      event.data.method === 'pickup' ? event.data.pickupLocation : null,
      event.data.method === 'pickup' && event.data.pickupAt ? fromBerlinInput(event.data.pickupAt) : null
    )
    open.value = false
    toast.add({
      title: props.requests.length === 1 ? 'Hinterlegung gespeichert' : `Hinterlegung für ${props.requests.length} Tickets gespeichert`,
      color: 'success',
      icon: 'i-lucide-check'
    })
    emit('saved')
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UModal
    v-model:open="open"
    title="Hinterlegung festlegen"
    :description="requests.length === 1
      ? `Für das Ticket von ${requests[0]?.holderName}.`
      : `Für ${requests.length} zugeteilte Tickets.`"
  >
    <template #body>
      <UForm
        :schema="ticketDeliverySchema"
        :state="state"
        class="space-y-4"
        @submit="onSubmit"
      >
        <UFormField name="method">
          <URadioGroup
            v-model="state.method"
            :items="methodItems"
            variant="card"
          />
        </UFormField>

        <template v-if="state.method === 'pickup'">
          <UFormField
            name="pickupLocation"
            label="Abholort"
            required
          >
            <UInput
              v-model="state.pickupLocation"
              placeholder="z. B. am Bus vor der Abfahrt"
              size="lg"
              class="w-full"
            />
          </UFormField>
          <UFormField
            name="pickupAt"
            label="Abholzeit"
            hint="Optional"
          >
            <UInput
              v-model="state.pickupAt"
              type="datetime-local"
              size="lg"
              class="w-full"
            />
          </UFormField>
        </template>

        <UAlert
          v-if="filesToRemove"
          color="warning"
          variant="subtle"
          icon="i-lucide-triangle-alert"
          :title="filesToRemove === 1 ? 'Ein hochgeladenes PDF wird gelöscht.' : `${filesToRemove} hochgeladene PDFs werden gelöscht.`"
        />

        <UButton
          type="submit"
          label="Speichern"
          size="lg"
          block
          loading-auto
        />
      </UForm>
    </template>
  </UModal>
</template>
