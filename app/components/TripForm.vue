<script setup lang="ts">
import type { FormSubmitEvent, RadioGroupItem } from '@nuxt/ui'
import type { TransportMode, TripInput } from '~/composables/useTrips'

const props = defineProps<{
  initial?: TripInput
  submitLabel: string
  save: (input: TripInput) => Promise<void>
}>()

const transportItems = (Object.keys(TRANSPORT_MODES) as TransportMode[]).map(value => ({
  value,
  label: TRANSPORT_MODES[value].label
})) satisfies RadioGroupItem[]

const state = reactive({
  transport: props.initial?.transport ?? 'bus',
  title: props.initial?.title ?? '',
  departureAt: toBerlinInput(props.initial?.departureAt),
  meetingPoint: props.initial?.meetingPoint ?? '',
  capacity: props.initial?.capacity ?? null,
  price: props.initial?.priceCents != null ? props.initial.priceCents / 100 : null,
  registrationDeadline: toBerlinInput(props.initial?.registrationDeadline),
  notes: props.initial?.notes ?? ''
})

async function onSubmit(event: FormSubmitEvent<TripForm>) {
  const data = event.data
  await props.save({
    transport: data.transport,
    title: data.title || null,
    departureAt: data.departureAt ? fromBerlinInput(data.departureAt) : null,
    meetingPoint: data.meetingPoint || null,
    capacity: data.capacity ?? null,
    priceCents: data.price != null ? Math.round(data.price * 100) : null,
    registrationDeadline: data.registrationDeadline ? fromBerlinInput(data.registrationDeadline) : null,
    notes: data.notes || null
  })
}
</script>

<template>
  <UForm
    :schema="tripFormSchema"
    :state="state"
    class="space-y-5"
    @submit="onSubmit"
  >
    <UFormField
      name="transport"
      label="Verkehrsmittel"
    >
      <URadioGroup
        v-model="state.transport"
        :items="transportItems"
        variant="card"
        orientation="horizontal"
        :ui="{ fieldset: 'grid grid-cols-3 gap-2' }"
      />
    </UFormField>

    <UFormField
      name="title"
      label="Bezeichnung"
      hint="Optional"
      help="Nur nötig bei mehreren Fahrten zum selben Spiel."
    >
      <UInput
        v-model="state.title"
        placeholder="z. B. Bus 1 oder Auto von Jonas"
        size="lg"
        class="w-full"
      />
    </UFormField>

    <UFormField
      name="departureAt"
      label="Abfahrt"
      hint="Optional"
      help="Kannst du später nachtragen."
    >
      <UInput
        v-model="state.departureAt"
        type="datetime-local"
        size="lg"
        class="w-full"
      />
    </UFormField>

    <UFormField
      name="meetingPoint"
      label="Treffpunkt"
      hint="Optional"
      help="Nur für Mitglieder des Fanclubs sichtbar."
    >
      <UInput
        v-model="state.meetingPoint"
        placeholder="z. B. Parkplatz Nord am Stadion"
        size="lg"
        class="w-full"
      />
    </UFormField>

    <div class="grid grid-cols-2 gap-4">
      <UFormField
        name="capacity"
        label="Plätze"
        hint="Optional"
      >
        <UInputNumber
          v-model="state.capacity"
          :min="1"
          :max="1000"
          placeholder="unbegrenzt"
          size="lg"
          class="w-full"
        />
      </UFormField>

      <UFormField
        name="price"
        label="Kosten p. P."
        hint="Optional"
      >
        <UInputNumber
          v-model="state.price"
          :min="0"
          :step="0.5"
          :format-options="{ style: 'currency', currency: 'EUR' }"
          locale="de-DE"
          placeholder="offen"
          size="lg"
          class="w-full"
        />
      </UFormField>
    </div>

    <UFormField
      name="registrationDeadline"
      label="Anmeldeschluss"
      hint="Optional"
    >
      <UInput
        v-model="state.registrationDeadline"
        type="datetime-local"
        size="lg"
        class="w-full"
      />
    </UFormField>

    <UFormField
      name="notes"
      label="Hinweise"
      hint="Optional"
    >
      <UTextarea
        v-model="state.notes"
        placeholder="z. B. Rückfahrt direkt nach Abpfiff"
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
