<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'
import type { TicketRoundInput } from '~/composables/useTickets'

const props = defineProps<{
  initial?: TicketRoundInput
  submitLabel: string
  save: (input: TicketRoundInput) => Promise<void>
}>()

interface CategoryState {
  id?: string
  name: string
  price: number | null
  quota: number | null
}

const state = reactive({
  requestDeadline: toBerlinInput(props.initial?.requestDeadline),
  maxTicketsPerMember: props.initial?.maxTicketsPerMember ?? null,
  membershipNumberRequired: props.initial?.membershipNumberRequired ?? false,
  downloadRequiresPayment: props.initial?.downloadRequiresPayment ?? false,
  notes: props.initial?.notes ?? '',
  categories: (props.initial?.categories.map(category => ({
    id: category.id,
    name: category.name,
    price: category.priceCents / 100,
    quota: category.quota
  })) ?? [{ name: 'Stehplatz', price: null, quota: null }]) as CategoryState[]
})

function addCategory() {
  state.categories.push({ name: '', price: null, quota: null })
}

function removeCategory(index: number) {
  state.categories.splice(index, 1)
}

async function onSubmit(event: FormSubmitEvent<TicketRoundForm>) {
  const data = event.data
  await props.save({
    requestDeadline: data.requestDeadline ? fromBerlinInput(data.requestDeadline) : null,
    maxTicketsPerMember: data.maxTicketsPerMember ?? null,
    membershipNumberRequired: data.membershipNumberRequired,
    downloadRequiresPayment: data.downloadRequiresPayment,
    notes: data.notes || null,
    categories: data.categories.map(category => ({
      id: category.id,
      name: category.name,
      priceCents: Math.round(category.price * 100),
      quota: category.quota ?? null
    }))
  })
}
</script>

<template>
  <UForm
    :schema="ticketRoundFormSchema"
    :state="state"
    class="space-y-5"
    @submit="onSubmit"
  >
    <UFormField
      name="requestDeadline"
      label="Anfragen möglich bis"
      hint="Optional"
      help="Danach nimmt die Abfrage keine Anfragen mehr an."
    >
      <UInput
        v-model="state.requestDeadline"
        type="datetime-local"
        size="lg"
        class="w-full"
      />
    </UFormField>

    <UFormField
      name="maxTicketsPerMember"
      label="Tickets pro Mitglied"
      hint="Optional"
      help="Leer lassen, wenn es keine Begrenzung gibt."
    >
      <UInputNumber
        v-model="state.maxTicketsPerMember"
        :min="1"
        :max="20"
        placeholder="unbegrenzt"
        size="lg"
        class="w-full"
      />
    </UFormField>

    <UFormField name="membershipNumberRequired">
      <USwitch
        v-model="state.membershipNumberRequired"
        label="Mitgliedsnummer erforderlich"
        description="Jede Anfrage braucht dann die Vereinsmitgliedsnummer des Inhabers."
      />
    </UFormField>

    <UFormField name="downloadRequiresPayment">
      <USwitch
        v-model="state.downloadRequiresPayment"
        label="PDF erst nach bestätigter Zahlung"
        description="Mitglieder können ihr Ticket-PDF erst herunterladen, wenn du die Zahlung bestätigt hast."
      />
    </UFormField>

    <UFormField
      name="categories"
      label="Kategorien"
      help="Das Kontingent kannst du auch später eintragen, sobald es feststeht."
    >
      <div class="space-y-3">
        <div
          v-for="(category, index) in state.categories"
          :key="category.id ?? `new-${index}`"
          class="space-y-3 rounded-md border border-default p-3"
        >
          <div class="flex items-start gap-2">
            <UFormField
              :name="`categories.${index}.name`"
              label="Name"
              class="flex-1"
            >
              <UInput
                v-model="category.name"
                placeholder="z. B. Stehplatz"
                size="lg"
                class="w-full"
              />
            </UFormField>
            <UButton
              icon="i-lucide-trash-2"
              color="neutral"
              variant="ghost"
              :disabled="state.categories.length === 1"
              aria-label="Kategorie entfernen"
              class="mt-6"
              @click="removeCategory(index)"
            />
          </div>

          <div class="grid grid-cols-2 gap-3">
            <UFormField
              :name="`categories.${index}.price`"
              label="Preis"
            >
              <UInputNumber
                v-model="category.price"
                :min="0"
                :step="0.5"
                :format-options="{ style: 'currency', currency: 'EUR' }"
                locale="de-DE"
                size="lg"
                class="w-full"
              />
            </UFormField>
            <UFormField
              :name="`categories.${index}.quota`"
              label="Kontingent"
            >
              <UInputNumber
                v-model="category.quota"
                :min="0"
                placeholder="offen"
                size="lg"
                class="w-full"
              />
            </UFormField>
          </div>
        </div>

        <UButton
          label="Kategorie hinzufügen"
          icon="i-lucide-plus"
          color="neutral"
          variant="outline"
          block
          @click="addCategory"
        />
      </div>
    </UFormField>

    <UFormField
      name="notes"
      label="Hinweise"
      hint="Optional"
    >
      <UTextarea
        v-model="state.notes"
        placeholder="z. B. Abholung, Ermäßigungsnachweis, Ansprechpartner"
        autoresize
        size="lg"
        class="w-full"
      />
    </UFormField>

    <UButton
      type="submit"
      :label="submitLabel"
      size="lg"
      block
      loading-auto
    />
  </UForm>
</template>
