<script setup lang="ts">
import type { TicketCategory, TicketRequest } from '~/composables/useTickets'

// Eine Zahlung für alle eigenen zugeteilten Tickets mit Preis innerhalb einer Ticketabfrage
const props = defineProps<{
  /** Eigene Anfragen dieser Abfrage */
  requests: TicketRequest[]
  categories: TicketCategory[]
  awayGame: { matchday: number, opponentName: string }
  paypalMe: string | null
}>()

const emit = defineEmits<{ changed: [] }>()

const { profile } = useProfile()
const { reportPayment } = usePaymentActions()

const priceOf = (categoryId: string) => props.categories.find(c => c.id === categoryId)?.priceCents ?? 0
const payable = computed(() => props.requests.filter(r => r.status === 'allocated' && priceOf(r.categoryId) > 0))
const status = computed(() => combinedPaymentStatus(payable.value.map(r => r.paymentStatus)))
const amount = computed(() => {
  const relevant = status.value === 'open'
    ? payable.value.filter(r => r.paymentStatus === 'open')
    : payable.value
  return relevant.reduce((sum, r) => sum + priceOf(r.categoryId), 0)
})
const reference = computed(() => paymentReference({
  what: payable.value.length === 1 ? 'Ticket' : `${payable.value.length} Tickets`,
  matchday: props.awayGame.matchday,
  opponentName: props.awayGame.opponentName,
  payerName: profile.value?.display_name ?? ''
}))

async function report() {
  await reportPayment({ ticketRequestIds: payable.value.filter(r => r.paymentStatus === 'open').map(r => r.id) })
  emit('changed')
}
</script>

<template>
  <template v-if="payable.length">
    <USeparator />
    <PaymentBox
      :label="payable.length === 1 ? 'Für dein Ticket' : `Für deine ${payable.length} Tickets`"
      :amount-cents="amount"
      :reference="reference"
      :paypal-me="paypalMe"
      :status="status"
      :report="report"
    />
  </template>
</template>
