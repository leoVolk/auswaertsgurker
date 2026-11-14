<script setup lang="ts">
import type { PaymentStatus } from '~/composables/usePayments'

// Bezahlen per PayPal.Me: Link mit Betrag, kopierbarer Verwendungszweck, Zahlung melden
const props = defineProps<{
  label: string
  amountCents: number
  reference: string
  paypalMe: string | null
  status: PaymentStatus
  report: () => Promise<void>
}>()

const toast = useToast()
const showError = useErrorToast()

async function copyReference() {
  try {
    await navigator.clipboard.writeText(props.reference)
    toast.add({ title: 'Verwendungszweck kopiert', color: 'success', icon: 'i-lucide-check' })
  } catch (error) {
    showError(error, 'Kopieren hat nicht geklappt. Markiere den Text und kopiere ihn von Hand.')
  }
}

async function onReport() {
  try {
    await props.report()
    toast.add({
      title: 'Zahlung gemeldet',
      description: 'Die Organisatoren bestätigen sie, wenn das Geld da ist.',
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <div class="space-y-3">
    <div class="flex items-baseline justify-between gap-3">
      <span class="text-sm text-muted">{{ label }}</span>
      <span class="text-lg font-semibold text-highlighted">{{ formatPrice(amountCents) }}</span>
    </div>

    <template v-if="status === 'open'">
      <template v-if="paypalMe">
        <UButton
          :to="paypalMeUrl(paypalMe, amountCents)"
          target="_blank"
          label="Mit PayPal bezahlen"
          icon="i-simple-icons-paypal"
          size="lg"
          block
        />

        <UFormField
          label="Verwendungszweck"
          help="Gib ihn bei PayPal als Nachricht an, damit die Organisatoren deine Zahlung zuordnen können."
        >
          <UFieldGroup class="w-full">
            <UInput
              :model-value="reference"
              readonly
              aria-label="Verwendungszweck"
              class="w-full"
              @focus="($event.target as HTMLInputElement).select()"
            />
            <UButton
              icon="i-lucide-copy"
              color="neutral"
              variant="subtle"
              aria-label="Verwendungszweck kopieren"
              @click="copyReference"
            />
          </UFieldGroup>
        </UFormField>

        <UButton
          label="Ich habe bezahlt"
          icon="i-lucide-check"
          color="neutral"
          variant="outline"
          size="lg"
          block
          loading-auto
          @click="onReport"
        />
      </template>

      <StatusLine
        v-else
        color="neutral"
        title="Der Fanclub hat noch keinen PayPal-Link hinterlegt."
        description="Frag die Organisatoren, wie du bezahlen kannst."
      />
    </template>

    <StatusLine
      v-else-if="status === 'reported'"
      color="warning"
      title="Zahlung gemeldet"
      description="Die Organisatoren bestätigen sie, wenn das Geld da ist."
    />
    <StatusLine
      v-else-if="status === 'confirmed'"
      color="success"
      title="Bezahlt"
    />
    <StatusLine
      v-else
      color="info"
      title="Erstattet"
    />
  </div>
</template>
