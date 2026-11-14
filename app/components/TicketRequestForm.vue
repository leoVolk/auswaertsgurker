<script setup lang="ts">
import type { FormSubmitEvent, RadioGroupItem } from '@nuxt/ui'
import type { TicketRound } from '~/composables/useTickets'

const props = defineProps<{
  round: TicketRound
  defaultHolderName: string
}>()

const emit = defineEmits<{ requested: [] }>()

const { requestTicket } = useTicketRequestActions()
const toast = useToast()
const showError = useErrorToast()

const schema = computed(() => ticketHolderSchema(props.round.membershipNumberRequired))

const categoryItems = computed(() => props.round.categories.map(category => ({
  value: category.id,
  label: category.name,
  description: formatPrice(category.priceCents)
})) satisfies RadioGroupItem[])

const state = reactive({
  categoryId: props.round.categories[0]?.id ?? '',
  holderName: props.defaultHolderName,
  membershipNumber: ''
})

async function onSubmit(event: FormSubmitEvent<TicketHolderForm>) {
  try {
    await requestTicket(state.categoryId, event.data.holderName, event.data.membershipNumber || null)
    toast.add({
      title: 'Ticket angefragt',
      description: 'Du bekommst Bescheid, wenn die Organisatoren zugeteilt haben.',
      color: 'success',
      icon: 'i-lucide-check'
    })
    // Weitere Anfragen sind meist für andere Personen
    state.holderName = ''
    state.membershipNumber = ''
    emit('requested')
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UForm
    :schema="schema"
    :state="state"
    class="space-y-4"
    @submit="onSubmit"
  >
    <UFormField
      v-if="categoryItems.length > 1"
      label="Kategorie"
    >
      <URadioGroup
        v-model="state.categoryId"
        :items="categoryItems"
        variant="list"
      />
    </UFormField>

    <TicketHolderFields
      v-model:holder-name="state.holderName"
      v-model:membership-number="state.membershipNumber"
      :membership-number-required="round.membershipNumberRequired"
    />

    <UButton
      type="submit"
      label="Ticket anfragen"
      icon="i-lucide-ticket"
      size="lg"
      block
      loading-auto
    />
  </UForm>
</template>
