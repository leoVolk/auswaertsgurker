<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { TicketCategory, TicketRequest } from '~/composables/useTickets'

const props = defineProps<{
  requests: TicketRequest[]
  categories: TicketCategory[]
  membershipNumberRequired: boolean
}>()

const emit = defineEmits<{ changed: [] }>()

const { cancelRequest } = useTicketRequestActions()
const toast = useToast()
const showError = useErrorToast()

const categoryById = computed(() => new Map(props.categories.map(category => [category.id, category])))

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
  <ul class="divide-y divide-default rounded-md border border-default">
    <li
      v-for="request in requests"
      :key="request.id"
      class="space-y-2 px-3 py-2.5"
      :class="{ 'opacity-60': request.status === 'cancelled' || request.status === 'rejected' }"
    >
      <div class="flex items-center gap-3">
        <span class="min-w-0 flex-1">
          <span class="block truncate font-medium text-highlighted">{{ request.holderName }}</span>
          <span class="block text-sm text-muted">
            {{ categoryLabel(request) }}
            <template v-if="request.holderMembershipNumber"> · Nr. {{ request.holderMembershipNumber }}</template>
          </span>
        </span>
        <UBadge
          :label="TICKET_STATUS[request.status].label"
          :color="TICKET_STATUS[request.status].color"
          variant="subtle"
          size="sm"
          class="shrink-0"
        />
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
        v-if="request.status === 'allocated'"
        :request="request"
      />
    </li>
  </ul>

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
