<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { TicketCategory, TicketRequest } from '~/composables/useTickets'

const props = defineProps<{
  requests: TicketRequest[]
  categories: TicketCategory[]
  membershipNumberRequired: boolean
  downloadRequiresPayment: boolean
  /** Ticketdaten nach Ablauf der Löschfrist entfernt */
  purged: boolean
}>()

function paymentBadge(request: TicketRequest) {
  if (request.status === 'allocated') {
    return (categoryById.value.get(request.categoryId)?.priceCents ?? 0) > 0
      ? PAYMENT_STATUS[request.paymentStatus]
      : null
  }
  return request.paymentStatus === 'confirmed'
    ? { label: 'Wird erstattet', color: 'info' as const }
    : null
}

const emit = defineEmits<{ changed: [] }>()

const { cancelRequest } = useTicketRequestActions()
const toast = useToast()
const showError = useErrorToast()

const categoryById = computed(() => new Map(props.categories.map(category => [category.id, category])))

// Stornierte stehen zugeklappt unter den übrigen Anfragen, ohne die durch eine neue Anfrage überholten
const activeRequests = computed(() => props.requests.filter(r => r.status !== 'cancelled'))
const cancelledRequests = computed(() =>
  withoutSupersededCancellations(props.requests).filter(r => r.status === 'cancelled')
)

function categoryLabel(request: TicketRequest) {
  const category = categoryById.value.get(request.categoryId)
  return category ? `${category.name} · ${formatPrice(category.priceCents)}` : ''
}

const editRequest = ref<TicketRequest | null>(null)
const editOpen = ref(false)
const cancelTarget = ref<TicketRequest | null>(null)
const cancelOpen = computed({
  get: () => cancelTarget.value !== null,
  set: (open) => {
    if (!open) cancelTarget.value = null
  }
})

function actions(request: TicketRequest): DropdownMenuItem[][] {
  return [
    [{
      label: 'Inhaber ändern',
      icon: 'i-lucide-pencil',
      onSelect: () => {
        editRequest.value = request
        editOpen.value = true
      }
    }],
    [{
      label: 'Anfrage stornieren',
      icon: 'i-lucide-x',
      color: 'error',
      onSelect: () => {
        cancelTarget.value = request
      }
    }]
  ]
}

async function onCancel() {
  const request = cancelTarget.value
  if (!request) return
  try {
    await cancelRequest(request.id)
    cancelTarget.value = null
    toast.add({ title: 'Anfrage storniert', color: 'success', icon: 'i-lucide-check' })
    emit('changed')
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <div class="space-y-3">
    <ul
      v-if="activeRequests.length"
      class="divide-y divide-default rounded-md border border-default"
    >
      <li
        v-for="request in activeRequests"
        :key="request.id"
        class="space-y-2 px-3 py-2.5"
        :class="{ 'opacity-60': request.status === 'rejected' }"
      >
        <div class="flex items-center gap-3">
          <span class="min-w-0 flex-1">
            <span class="block truncate font-medium text-highlighted">{{ request.holderName }}</span>
            <span class="block text-sm text-muted">
              {{ categoryLabel(request) }}
              <template v-if="request.holderMembershipNumber"> · Nr. {{ request.holderMembershipNumber }}</template>
            </span>
          </span>
          <!-- Zahlung (solid) und Status (subtle) nebeneinander, damit die Zeile nicht höher wird -->
          <span class="flex shrink-0 items-center gap-1">
            <UBadge
              v-if="paymentBadge(request)"
              :label="paymentBadge(request)?.label"
              :color="paymentBadge(request)?.color"
              variant="solid"
              size="sm"
            />
            <UBadge
              :label="TICKET_STATUS[request.status].label"
              :color="TICKET_STATUS[request.status].color"
              variant="subtle"
              size="sm"
            />
          </span>
          <UDropdownMenu
            v-if="request.status === 'requested' || request.status === 'waitlist'"
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
        </div>

        <TicketDeliveryInfo
          v-if="request.status === 'allocated' && !purged"
          :request="request"
          :download-requires-payment="downloadRequiresPayment"
        />
      </li>
    </ul>

    <UCollapsible
      v-if="cancelledRequests.length"
      class="flex flex-col gap-2"
    >
      <UButton
        :label="`Stornierte Anfragen (${cancelledRequests.length})`"
        color="neutral"
        variant="ghost"
        trailing-icon="i-lucide-chevron-down"
        block
        class="group justify-between text-muted"
        :ui="{ trailingIcon: 'transition-transform duration-200 group-data-[state=open]:rotate-180' }"
      />

      <template #content>
        <ul class="divide-y divide-default rounded-md border border-default">
          <li
            v-for="request in cancelledRequests"
            :key="request.id"
            class="flex items-center gap-3 px-3 py-2.5"
          >
            <span class="min-w-0 flex-1 opacity-60">
              <span class="block truncate font-medium text-highlighted">{{ request.holderName }}</span>
              <span class="block text-sm text-muted">{{ categoryLabel(request) }}</span>
            </span>
            <UBadge
              v-if="paymentBadge(request)"
              :label="paymentBadge(request)?.label"
              :color="paymentBadge(request)?.color"
              variant="solid"
              size="sm"
              class="shrink-0"
            />
          </li>
        </ul>
      </template>
    </UCollapsible>
  </div>

  <TicketHolderModal
    v-model:open="editOpen"
    :request="editRequest"
    :membership-number-required="membershipNumberRequired"
    @saved="emit('changed')"
  />

  <UModal
    v-model:open="cancelOpen"
    title="Anfrage stornieren?"
    :description="cancelTarget ? `Die Anfrage für ${cancelTarget.holderName} wird storniert.` : undefined"
  >
    <template #footer>
      <div class="flex w-full justify-end gap-2">
        <UButton
          label="Doch nicht"
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
</template>
