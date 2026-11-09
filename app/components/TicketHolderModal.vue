<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'
import type { TicketRequest } from '~/composables/useTickets'

const props = defineProps<{
  request: TicketRequest | null
  membershipNumberRequired: boolean
}>()

const emit = defineEmits<{ saved: [] }>()
const open = defineModel<boolean>('open', { required: true })

const { updateHolder } = useTicketRequestActions()
const toast = useToast()
const showError = useErrorToast()

const schema = computed(() => ticketHolderSchema(props.membershipNumberRequired))
const state = reactive({ holderName: '', membershipNumber: '' })

watch(() => props.request, (request) => {
  state.holderName = request?.holderName ?? ''
  state.membershipNumber = request?.holderMembershipNumber ?? ''
}, { immediate: true })

async function onSubmit(event: FormSubmitEvent<TicketHolderForm>) {
  if (!props.request) return
  try {
    await updateHolder(props.request.id, event.data.holderName, event.data.membershipNumber || null)
    open.value = false
    toast.add({ title: 'Inhaber geändert', color: 'success', icon: 'i-lucide-check' })
    emit('saved')
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UModal
    v-model:open="open"
    title="Inhaber ändern"
    description="Tickets dürfen nur zum Originalpreis weitergegeben werden."
  >
    <template #body>
      <UForm
        :schema="schema"
        :state="state"
        class="space-y-4"
        @submit="onSubmit"
      >
        <TicketHolderFields
          v-model:holder-name="state.holderName"
          v-model:membership-number="state.membershipNumber"
          :membership-number-required="membershipNumberRequired"
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
