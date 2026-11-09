<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'

definePageMeta({
  // Wer schon angemeldet ist, braucht die Seite nicht
  middleware: () => {
    if (useCurrentUserId().value) return navigateTo('/')
  }
})

useHead({ title: 'Anmelden' })

const supabase = useSupabaseClient()
const cookieRedirect = useSupabaseCookieRedirect()
const syncUser = useSyncSupabaseUser()
const toast = useToast()
const showError = useErrorToast()

const step = ref<'email' | 'code'>('email')
const emailState = reactive({ email: '' })
const codeState = reactive({ code: [] as number[] })
const codeForm = useTemplateRef('codeForm')

async function sendCode(email: string) {
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      shouldCreateUser: true,
      // Nur relevant, falls die E-Mail-Vorlage noch einen Link statt des Codes enthält
      emailRedirectTo: `${window.location.origin}/confirm`
    }
  })
  if (error) throw error
}

async function onEmailSubmit(event: FormSubmitEvent<EmailForm>) {
  try {
    await sendCode(event.data.email)
    emailState.email = event.data.email
    codeState.code = []
    step.value = 'code'
  } catch (error) {
    showError(error)
  }
}

async function onCodeSubmit(event: FormSubmitEvent<OtpForm>) {
  try {
    const { error } = await supabase.auth.verifyOtp({
      email: emailState.email,
      token: event.data.code,
      type: 'email'
    })
    if (error) throw error
    await syncUser()
    await navigateTo(safeRedirect(cookieRedirect.pluck()))
  } catch (error) {
    // Falscher Code: Felder leeren, damit man direkt neu tippen kann
    codeState.code = []
    showError(error)
  }
}

// Alle Ziffern da (getippt, eingefügt oder vom Handy vorgeschlagen): direkt abschicken
function onCodeComplete() {
  codeForm.value?.submit()
}

async function resendCode() {
  try {
    await sendCode(emailState.email)
    toast.add({ title: 'Neuer Code ist unterwegs', color: 'success', icon: 'i-lucide-mail' })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <div class="space-y-6">
    <div class="space-y-1">
      <h1 class="text-2xl font-bold text-highlighted">
        Anmelden
      </h1>
      <p class="text-muted">
        Du bekommst einen Code per E-Mail. Ein Passwort brauchst du nicht.
      </p>
    </div>

    <UCard>
      <UForm
        v-if="step === 'email'"
        :schema="emailSchema"
        :state="emailState"
        class="space-y-4"
        @submit="onEmailSubmit"
      >
        <UFormField
          name="email"
          label="E-Mail-Adresse"
        >
          <UInput
            v-model="emailState.email"
            type="email"
            autocomplete="email"
            placeholder="du@beispiel.de"
            size="lg"
            class="w-full"
            autofocus
          />
        </UFormField>

        <UButton
          type="submit"
          label="Code anfordern"
          size="lg"
          block
          loading-auto
        />
      </UForm>

      <UForm
        v-else
        ref="codeForm"
        :schema="otpSchema"
        :state="codeState"
        class="space-y-4"
        @submit="onCodeSubmit"
      >
        <UFormField
          name="code"
          label="Code aus der E-Mail"
          :description="`Wir haben dir einen ${OTP_LENGTH}-stelligen Code an ${emailState.email} geschickt. Schau auch im Spam-Ordner nach.`"
        >
          <!-- Felder teilen sich die Breite, damit 8 Stellen auch auf 375 px passen -->
          <UPinInput
            v-model="codeState.code"
            type="number"
            :length="OTP_LENGTH"
            :separator="OTP_LENGTH / 2"
            otp
            autofocus
            placeholder="○"
            size="xl"
            aria-label="Anmeldecode"
            :ui="{
              root: 'flex w-full max-w-sm gap-1.5',
              base: 'aspect-square h-auto w-auto min-w-0 flex-1 text-lg'
            }"
            @complete="onCodeComplete"
          />
        </UFormField>

        <UButton
          type="submit"
          label="Anmelden"
          size="lg"
          block
          loading-auto
        />

        <div class="flex flex-wrap justify-between gap-2">
          <UButton
            label="Andere E-Mail-Adresse"
            color="neutral"
            variant="link"
            class="-ms-2.5"
            @click="step = 'email'"
          />
          <UButton
            label="Code erneut senden"
            color="neutral"
            variant="link"
            class="-me-2.5"
            loading-auto
            @click="resendCode"
          />
        </div>
      </UForm>
    </UCard>
  </div>
</template>
