<script setup lang="ts">
import type { FormSubmitEvent, RadioGroupItem } from '@nuxt/ui'
import type { TicketRound } from '~/composables/useTickets'

const props = defineProps<{
  round: TicketRound
  /** Für die erste Anfrage der eigene Name, danach leer (weitere Tickets sind meist für andere) */
  defaultHolderName: string
}>()

const emit = defineEmits<{ requested: [] }>()

const { requestTicket } = useTicketRequestActions()
const { profile } = useProfile()
const { membershipNumber: ownNumber, save: saveOwnNumber } = await useMembershipNumber()
const toast = useToast()
const showError = useErrorToast()

const categoryItems = computed(() => props.round.categories.map(category => ({
  value: category.id,
  label: category.name,
  description: formatPrice(category.priceCents)
})) satisfies RadioGroupItem[])

const state = reactive({
  categoryId: props.round.categories[0]?.id ?? '',
  holderName: props.defaultHolderName,
  membershipNumber: props.defaultHolderName ? ownNumber.value ?? '' : '',
  remember: true
})

const normalize = (value: string) => value.trim().replace(/\s+/g, ' ').toLocaleLowerCase('de-DE')
const isForMe = computed(() =>
  !!profile.value?.display_name && normalize(state.holderName) === normalize(profile.value.display_name)
)

// Eigene Nummer eintragen, sobald man den eigenen Namen als Inhaber wählt
watch(isForMe, (forMe) => {
  if (forMe && !state.membershipNumber && ownNumber.value) {
    state.membershipNumber = ownNumber.value
  }
})

// Speichern anbieten, wenn man für sich selbst anfragt und die Nummer neu oder anders ist
const canRemember = computed(() =>
  isForMe.value && state.membershipNumber.trim() !== '' && state.membershipNumber.trim() !== ownNumber.value
)

async function onSubmit(event: FormSubmitEvent<TicketHolderForm>) {
  try {
    await requestTicket(state.categoryId, event.data.holderName, event.data.membershipNumber)
    if (canRemember.value && state.remember) {
      await saveOwnNumber(event.data.membershipNumber).catch(showError)
    }
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
    :schema="ticketHolderSchema"
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
    />

    <UCheckbox
      v-if="canRemember"
      v-model="state.remember"
      :label="ownNumber ? 'Gespeicherte Nummer im Profil ersetzen' : 'Nummer in meinem Profil speichern'"
      description="Dann ist sie bei deiner nächsten Anfrage schon eingetragen."
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
