<script setup lang="ts">
import type { TicketRequest } from '~/composables/useTickets'

// Wie ein Mitglied an sein zugeteiltes Ticket kommt
const props = defineProps<{
  request: TicketRequest
  /** PDF erst nach bestätigter Zahlung abrufbar */
  downloadRequiresPayment: boolean
}>()

const downloadLocked = computed(() =>
  props.downloadRequiresPayment && props.request.paymentStatus !== 'confirmed'
)

const openTicketFile = useOpenTicketFile()
const showError = useErrorToast()

async function download() {
  if (!props.request.ticketFilePath) return
  try {
    await openTicketFile(props.request.ticketFilePath, props.request.holderName)
  } catch (error) {
    showError(error, 'Das Ticket konnte nicht geladen werden.')
  }
}
</script>

<template>
  <div class="rounded-md bg-elevated/50 p-3 text-sm">
    <template v-if="request.deliveryMethod === 'digital'">
      <p
        v-if="request.ticketFilePath && downloadLocked"
        class="flex gap-2 text-muted"
      >
        <UIcon
          name="i-lucide-lock"
          class="mt-0.5 size-4 shrink-0"
        />
        Dein Ticket ist da. Herunterladen kannst du es, wenn deine Zahlung bestätigt ist.
      </p>
      <UButton
        v-else-if="request.ticketFilePath"
        label="Ticket herunterladen (PDF)"
        icon="i-lucide-download"
        block
        loading-auto
        @click="download"
      />
      <p
        v-else
        class="flex gap-2 text-muted"
      >
        <UIcon
          name="i-lucide-file-text"
          class="mt-0.5 size-4 shrink-0"
        />
        Dein Ticket kommt als PDF. Du bekommst Bescheid, wenn es da ist.
      </p>
    </template>

    <p
      v-else-if="request.deliveryMethod === 'pickup'"
      class="flex gap-2 text-highlighted"
    >
      <UIcon
        name="i-lucide-map-pin"
        class="mt-0.5 size-4 shrink-0 text-primary"
      />
      <span>
        Abholung: {{ request.pickupLocation }}<template v-if="request.pickupAt">, {{ formatDateTime(request.pickupAt) }}</template>
      </span>
    </p>

    <p
      v-else-if="request.deliveryMethod === 'box_office'"
      class="flex gap-2 text-highlighted"
    >
      <UIcon
        name="i-lucide-store"
        class="mt-0.5 size-4 shrink-0 text-primary"
      />
      Hinterlegt an der Gästekasse auf den Namen {{ request.holderName }}.
    </p>

    <p
      v-else
      class="flex gap-2 text-muted"
    >
      <UIcon
        name="i-lucide-info"
        class="mt-0.5 size-4 shrink-0"
      />
      Wie du an dein Ticket kommst, steht noch nicht fest.
    </p>
  </div>
</template>
