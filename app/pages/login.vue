<script setup lang="ts">
import type { FormSubmitEvent, TabsItem } from '@nuxt/ui'

definePageMeta({
  // Wer schon angemeldet ist, braucht die Seite nicht
  middleware: () => {
    if (useCurrentUserId().value) return navigateTo('/')
  }
})

useHead({ title: 'Anmelden' })

type LoginMethod = 'code' | 'password'

const supabase = useSupabaseClient()
const cookieRedirect = useSupabaseCookieRedirect()
const syncUser = useSyncSupabaseUser()
const toast = useToast()
const showError = useErrorToast()

// Zuletzt erfolgreich genutzte Methode: Wer ein Passwort hat, landet direkt im richtigen Tab
const lastMethod = useCookie<LoginMethod | null>('login-method', { maxAge: 60 * 60 * 24 * 365, sameSite: 'lax' })
const method = ref<string>(lastMethod.value === 'password' ? 'password' : 'code')

const methodItems = [
  { label: 'Code per E-Mail', icon: 'i-lucide-mail', value: 'code', slot: 'code' as const },
  { label: 'Passwort', icon: 'i-lucide-key-round', value: 'password', slot: 'password' as const }
] satisfies TabsItem[]

// E-Mail-Adresse und Passwort gelten für beide Tabs
const loginState = reactive({ email: '', password: '' })

const step = ref<'email' | 'code'>('email')
// Adresse, an die der Code ging
const codeEmail = ref('')
const codeState = reactive({ code: [] as number[] })
const codeForm = useTemplateRef('codeForm')

async function finishLogin(used: LoginMethod) {
  lastMethod.value = used
  await syncUser()
  await navigateTo(safeRedirect(cookieRedirect.pluck()))
}

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
    codeEmail.value = event.data.email
    codeState.code = []
    step.value = 'code'
  } catch (error) {
    showError(error)
  }
}

async function onCodeSubmit(event: FormSubmitEvent<OtpForm>) {
  try {
    const { error } = await supabase.auth.verifyOtp({
      email: codeEmail.value,
      token: event.data.code,
      type: 'email'
    })
    if (error) throw error
    await finishLogin('code')
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
    await sendCode(codeEmail.value)
    toast.add({ title: 'Neuer Code ist unterwegs', color: 'success', icon: 'i-lucide-mail' })
  } catch (error) {
    showError(error)
  }
}

async function onPasswordSubmit(event: FormSubmitEvent<PasswordLoginForm>) {
  try {
    const { error } = await supabase.auth.signInWithPassword({
      email: event.data.email,
      password: event.data.password
    })
    if (error) throw error
    await finishLogin('password')
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
        Mit einem Code per E-Mail oder mit Passwort, wenn du im Profil eins festgelegt hast.
      </p>
    </div>

    <UCard>
      <UTabs
        v-model="method"
        :items="methodItems"
        class="w-full gap-4"
      >
        <template #code>
          <UForm
            v-if="step === 'email'"
            :schema="emailSchema"
            :state="loginState"
            class="space-y-4"
            @submit="onEmailSubmit"
          >
            <UFormField
              name="email"
              label="E-Mail-Adresse"
            >
              <UInput
                v-model="loginState.email"
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
              :description="`Wir haben dir einen ${OTP_LENGTH}-stelligen Code an ${codeEmail} geschickt. Schau auch im Spam-Ordner nach.`"
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
        </template>

        <template #password>
          <UForm
            :schema="passwordLoginSchema"
            :state="loginState"
            class="space-y-4"
            @submit="onPasswordSubmit"
          >
            <UFormField
              name="email"
              label="E-Mail-Adresse"
            >
              <UInput
                v-model="loginState.email"
                type="email"
                autocomplete="username"
                placeholder="du@beispiel.de"
                size="lg"
                class="w-full"
                autofocus
              />
            </UFormField>

            <UFormField
              name="password"
              label="Passwort"
            >
              <PasswordInput
                v-model="loginState.password"
                autocomplete="current-password"
              />
            </UFormField>

            <UButton
              type="submit"
              label="Anmelden"
              size="lg"
              block
              loading-auto
            />

            <p class="text-sm text-muted">
              Noch kein Passwort oder vergessen? Melde dich per Code an und leg es danach im Profil fest.
            </p>
          </UForm>
        </template>
      </UTabs>
    </UCard>
  </div>
</template>
