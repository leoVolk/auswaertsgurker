<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { PaymentStatus } from '~/composables/usePayments'
import type { TicketCategory, TicketRequest, TicketRound, TicketStatus } from '~/composables/useTickets'
import type { ExportList } from '~/utils/exportList'

const props = defineProps<{
  round: TicketRound
  requests: TicketRequest[]
  clubName: string
}>()

const emit = defineEmits<{ changed: [] }>()

const { setStatus, cancelRequest, autoAllocate } = useTicketRequestActions()
const { removeTicketFile } = useTicketFileActions(() => props.round.clubId)
const openTicketFile = useOpenTicketFile()
const toast = useToast()
const showError = useErrorToast()

const allocatedRequests = computed(() => props.requests.filter(r => r.status === 'allocated'))

// Zahlungen
const { setPaymentStatus } = usePaymentActions()
const priceOf = (categoryId: string) => props.round.categories.find(c => c.id === categoryId)?.priceCents ?? 0
const payableRequests = computed(() => allocatedRequests.value.filter(r => priceOf(r.categoryId) > 0))
const payment = computed(() => {
  const count = (status: PaymentStatus) => payableRequests.value.filter(r => r.paymentStatus === status).length
  return {
    confirmed: count('confirmed'),
    reported: count('reported'),
    open: count('open'),
    reportedIds: payableRequests.value.filter(r => r.paymentStatus === 'reported').map(r => r.id)
  }
})

/** Badge zur Zahlung; bei nicht mehr zugeteilten, aber bezahlten Tickets ein Hinweis zur Erstattung */
function paymentBadge(request: TicketRequest) {
  if (request.status !== 'allocated') {
    return request.paymentStatus === 'confirmed'
      ? { label: 'Erstattung offen', color: 'warning' as const }
      : null
  }
  return priceOf(request.categoryId) > 0 ? PAYMENT_STATUS[request.paymentStatus] : null
}

async function onSetPayment(request: TicketRequest, status: Exclude<PaymentStatus, 'reported'>) {
  await run(() => setPaymentStatus(status, { ticketRequestIds: [request.id] }), `Zahlung von ${request.holderName} aktualisiert`)
}

async function onConfirmReported() {
  await run(
    () => setPaymentStatus('confirmed', { ticketRequestIds: payment.value.reportedIds }),
    payment.value.reportedIds.length === 1 ? '1 Zahlung bestätigt' : `${payment.value.reportedIds.length} Zahlungen bestätigt`
  )
}

// PDF-Upload (einzeln oder gesammelt)
const uploadTarget = ref<TicketRequest | null>(null)
const uploadOpen = ref(false)

function openUpload(target: TicketRequest | null) {
  uploadTarget.value = target
  uploadOpen.value = true
}

/** Stand des Ticket-PDFs in der Liste (Tickets kommen immer als PDF) */
function deliveryLine(request: TicketRequest) {
  if (request.status !== 'allocated') {
    return request.ticketFilePath
      ? { icon: 'i-lucide-file-warning', text: 'PDF noch hinterlegt', class: 'text-warning' }
      : null
  }
  return request.ticketFilePath
    ? { icon: 'i-lucide-file-check', text: 'PDF hinterlegt', class: 'text-success' }
    : { icon: 'i-lucide-file-x', text: 'PDF fehlt', class: 'text-warning' }
}

function ticketActions(request: TicketRequest): DropdownMenuItem[] {
  const items: DropdownMenuItem[] = []
  if (request.status === 'allocated') {
    items.push({
      label: request.ticketFilePath ? 'PDF ersetzen' : 'PDF hochladen',
      icon: 'i-lucide-file-up',
      onSelect: () => openUpload(request)
    })
  }
  if (request.ticketFilePath) {
    const path = request.ticketFilePath
    items.push(
      {
        label: 'PDF ansehen',
        icon: 'i-lucide-eye',
        onSelect: async () => {
          try {
            await openTicketFile(path, request.holderName)
          } catch (error) {
            showError(error, 'Das PDF konnte nicht geladen werden.')
          }
        }
      },
      {
        label: 'PDF entfernen',
        icon: 'i-lucide-file-minus',
        onSelect: () => run(() => removeTicketFile(request.id), `PDF von ${request.holderName} entfernt`)
      }
    )
  }
  return items
}

// Jede Statusgruppe ist aufklappbar; offen startet nur „Angefragt“, weil dort Entscheidungen anstehen
const STATUS_ORDER: TicketStatus[] = ['requested', 'waitlist', 'allocated', 'rejected', 'cancelled']

// Über alle Kategorien, damit auch eine neue Anfrage in einer anderen Kategorie die Stornierung überholt
const listedRequests = computed(() => withoutSupersededCancellations(props.requests))

const categories = computed(() => props.round.categories.map((category) => {
  const requests = listedRequests.value.filter(r => r.categoryId === category.id)
  const count = (status: TicketStatus) => requests.filter(r => r.status === status).length
  return {
    ...category,
    allocated: count('allocated'),
    pending: count('requested') + count('waitlist'),
    groups: STATUS_ORDER
      .map((status) => {
        const items = requests.filter(r => r.status === status)
        return {
          status,
          items,
          // Bezahlt, aber nicht (mehr) zugeteilt: Organisatoren müssen erstatten
          refundsOpen: status === 'allocated' ? 0 : items.filter(r => r.paymentStatus === 'confirmed').length
        }
      })
      .filter(group => group.items.length > 0)
  }
}))

async function run(action: () => Promise<unknown>, success: string) {
  try {
    await action()
    toast.add({ title: success, color: 'success', icon: 'i-lucide-check' })
    emit('changed')
  } catch (error) {
    showError(error)
  }
}

async function onAutoAllocate(category: TicketCategory) {
  try {
    const result = await autoAllocate(category.id)
    toast.add({
      title: `${category.name}: ${result.allocated} zugeteilt`,
      description: result.waitlisted ? `${result.waitlisted} auf die Warteliste gesetzt.` : undefined,
      color: 'success',
      icon: 'i-lucide-check'
    })
    emit('changed')
  } catch (error) {
    showError(error)
  }
}

// Inhaber ändern
const editRequest = ref<TicketRequest | null>(null)
const editOpen = ref(false)

// Stornieren mit Rückfrage
const cancelTarget = ref<TicketRequest | null>(null)
const cancelOpen = computed({
  get: () => cancelTarget.value !== null,
  set: (open) => {
    if (!open) cancelTarget.value = null
  }
})

async function onCancel() {
  const request = cancelTarget.value
  if (!request) return
  await run(() => cancelRequest(request.id), `Anfrage von ${request.holderName} storniert`)
  cancelTarget.value = null
}

function actions(request: TicketRequest): DropdownMenuItem[][] {
  const paymentItems = (request.status === 'allocated' && priceOf(request.categoryId) > 0) || request.paymentStatus !== 'open'
    ? paymentMenuItems(request.paymentStatus, status => onSetPayment(request, status))
    : []

  // Stornierte: nur noch Zahlung (z. B. Erstattung) und PDF aufräumen
  if (request.status === 'cancelled') {
    return [paymentItems, ticketActions(request)].filter(group => group.length > 0)
  }

  const statusActions: DropdownMenuItem[] = []
  if (request.status !== 'allocated') {
    statusActions.push({
      label: 'Zuteilen',
      icon: 'i-lucide-ticket-check',
      onSelect: () => run(() => setStatus(request.id, 'allocated'), `Ticket für ${request.holderName} zugeteilt`)
    })
  }
  if (request.status !== 'waitlist') {
    statusActions.push({
      label: 'Auf die Warteliste',
      icon: 'i-lucide-list-ordered',
      onSelect: () => run(() => setStatus(request.id, 'waitlist'), `${request.holderName} steht auf der Warteliste`)
    })
  }
  if (request.status !== 'rejected') {
    statusActions.push({
      label: 'Ablehnen',
      icon: 'i-lucide-ban',
      onSelect: () => run(() => setStatus(request.id, 'rejected'), `Anfrage von ${request.holderName} abgelehnt`)
    })
  }

  return [
    statusActions,
    paymentItems,
    ticketActions(request),
    [{
      label: 'Inhaber ändern',
      icon: 'i-lucide-pencil',
      onSelect: () => {
        editRequest.value = request
        editOpen.value = true
      }
    }],
    [{
      label: 'Stornieren',
      icon: 'i-lucide-x',
      color: 'error',
      onSelect: () => {
        cancelTarget.value = request
      }
    }]
  ]
}

// Liste der zugeteilten Tickets, z. B. für die Ticketstelle des Vereins
async function copyAllocatedList() {
  const lines = categories.value.flatMap((category) => {
    const allocated = props.requests.filter(r => r.categoryId === category.id && r.status === 'allocated')
    if (!allocated.length) return []
    return [
      `${category.name} (${allocated.length})`,
      ...allocated.map(r => `- ${r.holderName}${r.holderMembershipNumber ? ` (Nr. ${r.holderMembershipNumber})` : ''}`),
      ''
    ]
  })
  if (!lines.length) {
    toast.add({ title: 'Noch keine Tickets zugeteilt', color: 'neutral', icon: 'i-lucide-info' })
    return
  }
  try {
    await navigator.clipboard.writeText(lines.join('\n').trim())
    toast.add({ title: 'Liste kopiert', color: 'success', icon: 'i-lucide-check' })
  } catch (error) {
    showError(error, 'Kopieren hat nicht geklappt.')
  }
}

// Export aller Anfragen (ohne stornierte), sortiert nach Kategorie und Status
function ticketExportList(): ExportList<TicketRequest> {
  const categoryOrder = new Map(props.round.categories.map((category, index) => [category.id, index]))
  const categoryName = new Map(props.round.categories.map(category => [category.id, category.name]))
  const rows = props.requests
    .filter(request => request.status !== 'cancelled')
    .sort((a, b) => (categoryOrder.get(a.categoryId) ?? 0) - (categoryOrder.get(b.categoryId) ?? 0)
      || STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status))
  const game = `${props.round.awayGame.matchday}. Spieltag bei ${props.round.awayGame.opponentName}`

  return {
    title: `Tickets bei ${props.round.awayGame.opponentName}`,
    subtitle: `${props.clubName} · ${game}`,
    fileName: exportFileName('tickets', props.round.awayGame.matchday, 'spieltag', props.round.awayGame.opponentName),
    rows,
    columns: [
      { header: 'Kategorie', value: r => categoryName.get(r.categoryId), width: 14 },
      { header: 'Inhaber', value: r => r.holderName, width: 24 },
      { header: 'Mitgliedsnummer', value: r => r.holderMembershipNumber, width: 18 },
      { header: 'Status', value: r => TICKET_STATUS[r.status].label, width: 12 },
      { header: 'Zahlung', value: r => paymentBadge(r)?.label, width: 16 },
      { header: 'Angefragt von', value: r => r.requesterName, width: 20 }
    ]
  }
}

// Export und seltene Werkzeuge gesammelt im Menü „Aktionen“
const toolItems = computed<DropdownMenuItem[][]>(() => [
  exportMenuItems(ticketExportList, error => showError(error, 'Der Export hat nicht geklappt.')),
  [
    { label: 'Zugeteilte als Text kopieren', icon: 'i-lucide-clipboard-list', onSelect: copyAllocatedList },
    ...(allocatedRequests.value.length
      ? [{ label: 'PDFs hochladen', icon: 'i-lucide-file-up', onSelect: () => openUpload(null) }]
      : [])
  ]
])
</script>

<template>
  <section class="space-y-6">
    <div class="space-y-3">
      <div class="flex items-center gap-3">
        <p
          v-if="payableRequests.length"
          class="text-sm text-muted"
        >
          Bezahlt {{ payment.confirmed }} · Gemeldet {{ payment.reported }} · Offen {{ payment.open }}
        </p>
        <UDropdownMenu
          :items="toolItems"
          :content="{ align: 'end' }"
        >
          <UButton
            label="Aktionen"
            trailing-icon="i-lucide-chevron-down"
            color="neutral"
            variant="outline"
            size="sm"
            class="ms-auto shrink-0"
          />
        </UDropdownMenu>
      </div>
      <UButton
        v-if="payment.reported"
        :label="`Gemeldete Zahlungen bestätigen (${payment.reported})`"
        icon="i-lucide-badge-check"
        variant="soft"
        block
        loading-auto
        @click="onConfirmReported"
      />
    </div>

    <div class="divide-y divide-default">
      <section
        v-for="category in categories"
        :key="category.id"
        class="space-y-3 py-6 first:pt-0 last:pb-0"
      >
        <div class="space-y-2">
          <div class="flex items-baseline justify-between gap-3">
            <h3 class="font-semibold text-highlighted">
              {{ category.name }} · {{ formatPrice(category.priceCents) }}
            </h3>
            <span class="shrink-0 text-sm text-muted">
              {{ category.quota !== null ? `${category.allocated} / ${category.quota} zugeteilt` : `${category.allocated} zugeteilt` }}
            </span>
          </div>
          <UProgress
            v-if="category.quota"
            :model-value="Math.min(category.allocated, category.quota)"
            :max="category.quota"
            size="sm"
          />
          <p
            v-if="category.quota === null"
            class="text-sm text-muted"
          >
            Kontingent noch offen. Ohne Kontingent kannst du nicht automatisch zuteilen.
          </p>
        </div>

        <UButton
          v-if="category.quota !== null && category.pending > 0"
          label="Automatisch zuteilen"
          icon="i-lucide-wand-sparkles"
          variant="soft"
          block
          loading-auto
          @click="onAutoAllocate(category)"
        />

        <p
          v-if="!category.groups.length"
          class="text-sm text-muted"
        >
          Noch keine Anfragen.
        </p>

        <UCollapsible
          v-for="group in category.groups"
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
            <!-- Farbpunkt statt Badge, damit die Gruppentitel ruhig bleiben -->
            <span class="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-sm">
              <UChip
                standalone
                inset
                :color="TICKET_STATUS[group.status].color"
              />
              <span class="font-medium text-highlighted">
                {{ TICKET_STATUS[group.status].label }} ({{ group.items.length }})
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
            <TicketRequestRows
              :requests="group.items"
              :dimmed="group.status === 'rejected' || group.status === 'cancelled'"
              :delivery-line="deliveryLine"
              :payment-badge="paymentBadge"
              :actions="actions"
            />
          </template>
        </UCollapsible>
      </section>
    </div>

    <TicketHolderModal
      v-model:open="editOpen"
      :request="editRequest"
      @saved="emit('changed')"
    />

    <TicketFileUploadModal
      v-model:open="uploadOpen"
      :club-id="round.clubId"
      :categories="round.categories"
      :candidates="allocatedRequests"
      :target="uploadTarget"
      @uploaded="emit('changed')"
    />

    <UModal
      v-model:open="cancelOpen"
      title="Anfrage stornieren?"
      :description="cancelTarget
        ? cancelTarget.status === 'allocated'
          ? `Das zugeteilte Ticket von ${cancelTarget.holderName} wird storniert und ist danach wieder frei.`
          : `Die Anfrage von ${cancelTarget.holderName} wird storniert.`
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
            label="Stornieren"
            color="error"
            loading-auto
            @click="onCancel"
          />
        </div>
      </template>
    </UModal>
  </section>
</template>
