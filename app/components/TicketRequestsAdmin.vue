<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { TicketCategory, TicketRequest, TicketRound, TicketStatus } from '~/composables/useTickets'

const props = defineProps<{
  round: TicketRound
  requests: TicketRequest[]
}>()

const emit = defineEmits<{ changed: [] }>()

const { setStatus, cancelRequest, autoAllocate } = useTicketRequestActions()
const { removeTicketFile } = useTicketDeliveryActions(() => props.round.clubId)
const openTicketFile = useOpenTicketFile()
const toast = useToast()
const showError = useErrorToast()

const allocatedRequests = computed(() => props.requests.filter(r => r.status === 'allocated'))

// Hinterlegung festlegen (einzeln oder für alle zugeteilten Tickets)
const deliveryTargets = ref<TicketRequest[]>([])
const deliveryOpen = ref(false)

function openDelivery(targets: TicketRequest[]) {
  deliveryTargets.value = targets
  deliveryOpen.value = true
}

// PDF-Upload (einzeln oder gesammelt)
const uploadTarget = ref<TicketRequest | null>(null)
const uploadOpen = ref(false)

function openUpload(target: TicketRequest | null) {
  uploadTarget.value = target
  uploadOpen.value = true
}

/** Kurzinfo zur Hinterlegung eines Tickets in der Liste */
function deliveryLine(request: TicketRequest) {
  if (request.status !== 'allocated') {
    return request.ticketFilePath
      ? { icon: 'i-lucide-file-warning', text: 'PDF noch hinterlegt', class: 'text-warning' }
      : null
  }
  switch (request.deliveryMethod) {
    case 'digital':
      return request.ticketFilePath
        ? { icon: 'i-lucide-file-check', text: 'PDF hinterlegt', class: 'text-success' }
        : { icon: 'i-lucide-file-x', text: 'PDF fehlt', class: 'text-warning' }
    case 'pickup':
      return {
        icon: 'i-lucide-map-pin',
        text: `Abholung: ${request.pickupLocation}${request.pickupAt ? `, ${formatDateTime(request.pickupAt)}` : ''}`,
        class: 'text-muted'
      }
    case 'box_office':
      return { icon: 'i-lucide-store', text: 'Gästekasse', class: 'text-muted' }
    default:
      return { icon: 'i-lucide-circle-dashed', text: 'Hinterlegung offen', class: 'text-muted' }
  }
}

function ticketActions(request: TicketRequest): DropdownMenuItem[] {
  const items: DropdownMenuItem[] = []
  if (request.status === 'allocated') {
    items.push(
      {
        label: request.ticketFilePath ? 'PDF ersetzen' : 'PDF hochladen',
        icon: 'i-lucide-file-up',
        onSelect: () => openUpload(request)
      },
      {
        label: 'Hinterlegung festlegen',
        icon: 'i-lucide-package-check',
        onSelect: () => openDelivery([request])
      }
    )
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

const STATUS_ORDER: TicketStatus[] = ['requested', 'waitlist', 'allocated', 'rejected', 'cancelled']

const categories = computed(() => props.round.categories.map((category) => {
  const requests = props.requests.filter(r => r.categoryId === category.id)
  const count = (status: TicketStatus) => requests.filter(r => r.status === status).length
  return {
    ...category,
    allocated: count('allocated'),
    pending: count('requested') + count('waitlist'),
    groups: STATUS_ORDER
      .map(status => ({ status, items: requests.filter(r => r.status === status) }))
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
</script>

<template>
  <section class="space-y-3">
    <h2 class="text-lg font-semibold text-highlighted">
      Alle Anfragen
    </h2>
    <div class="flex flex-wrap gap-2">
      <UButton
        label="Liste kopieren"
        icon="i-lucide-clipboard-list"
        color="neutral"
        variant="outline"
        size="sm"
        @click="copyAllocatedList"
      />
      <template v-if="allocatedRequests.length">
        <UButton
          label="PDFs hochladen"
          icon="i-lucide-file-up"
          color="neutral"
          variant="outline"
          size="sm"
          @click="openUpload(null)"
        />
        <UButton
          label="Hinterlegung für alle"
          icon="i-lucide-package-check"
          color="neutral"
          variant="outline"
          size="sm"
          @click="openDelivery(allocatedRequests)"
        />
      </template>
    </div>

    <UCard
      v-for="category in categories"
      :key="category.id"
      :ui="{ body: 'space-y-4' }"
    >
      <template #header>
        <div class="space-y-2">
          <div class="flex items-center justify-between gap-3">
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
            Kontingent noch offen. Trag es beim Bearbeiten ein, um automatisch zuteilen zu können.
          </p>
        </div>
      </template>

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

      <section
        v-for="group in category.groups"
        :key="group.status"
        class="space-y-2"
      >
        <h4 class="flex items-center gap-2 text-sm text-muted">
          <UBadge
            :label="TICKET_STATUS[group.status].label"
            :color="TICKET_STATUS[group.status].color"
            variant="subtle"
            size="sm"
          />
          {{ group.items.length }}
        </h4>
        <ul class="divide-y divide-default rounded-md border border-default">
          <li
            v-for="request in group.items"
            :key="request.id"
            class="flex items-center gap-3 px-3 py-2"
            :class="{ 'opacity-60': group.status === 'cancelled' || group.status === 'rejected' }"
          >
            <span class="min-w-0 flex-1">
              <span class="block truncate font-medium text-highlighted">{{ request.holderName }}</span>
              <span class="block truncate text-sm text-muted">
                <template v-if="request.requesterName !== request.holderName">über {{ request.requesterName }}</template>
                <template v-if="request.requesterName !== request.holderName && request.holderMembershipNumber"> · </template>
                <template v-if="request.holderMembershipNumber">Nr. {{ request.holderMembershipNumber }}</template>
              </span>
              <span
                v-if="deliveryLine(request)"
                class="flex items-center gap-1.5 text-sm"
                :class="deliveryLine(request)?.class"
              >
                <UIcon
                  :name="deliveryLine(request)?.icon ?? ''"
                  class="size-4 shrink-0"
                />
                <span class="truncate">{{ deliveryLine(request)?.text }}</span>
              </span>
            </span>
            <UDropdownMenu
              v-if="group.status !== 'cancelled'"
              :items="actions(request)"
              :content="{ align: 'end' }"
            >
              <UButton
                icon="i-lucide-ellipsis-vertical"
                color="neutral"
                variant="ghost"
                :aria-label="`Aktionen für ${request.holderName}`"
              />
            </UDropdownMenu>
          </li>
        </ul>
      </section>
    </UCard>

    <TicketHolderModal
      v-model:open="editOpen"
      :request="editRequest"
      :membership-number-required="round.membershipNumberRequired"
      @saved="emit('changed')"
    />

    <TicketDeliveryModal
      v-model:open="deliveryOpen"
      :club-id="round.clubId"
      :requests="deliveryTargets"
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
