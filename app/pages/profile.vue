<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'

useHead({ title: 'Profil' })

const { profile, fetchProfile, updateDisplayName, updateEmailNotifications } = useProfile()
const user = useSupabaseUser()
const hasPassword = useHasPassword()
const setPassword = useSetPassword()
const push = usePushNotifications()
const installPrompt = useInstallPrompt()
const toast = useToast()
const showError = useErrorToast()

await fetchProfile()

async function saveName(displayName: string) {
  try {
    await updateDisplayName(displayName)
    toast.add({ title: 'Name gespeichert', color: 'success', icon: 'i-lucide-check' })
  } catch (error) {
    showError(error)
  }
}

const passwordState = reactive({ password: '' })
const changingPassword = ref(false)

async function savePassword(event: FormSubmitEvent<NewPasswordForm>) {
  const hadPassword = hasPassword.value
  try {
    await setPassword(event.data.password)
    passwordState.password = ''
    // Formular schließen: Passwort-Manager werten das als erfolgreiches Absenden
    changingPassword.value = false
    toast.add({
      title: hadPassword ? 'Passwort geändert' : 'Passwort festgelegt',
      description: 'Beim nächsten Anmelden kannst du den Tab „Passwort“ nutzen.',
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  }
}

function cancelPasswordChange() {
  passwordState.password = ''
  changingPassword.value = false
}

const emailSaving = ref(false)

async function toggleEmail(enabled: boolean) {
  emailSaving.value = true
  try {
    await updateEmailNotifications(enabled)
    toast.add({
      title: enabled ? 'E-Mail-Benachrichtigungen an' : 'E-Mail-Benachrichtigungen aus',
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  } finally {
    emailSaving.value = false
  }
}

async function enablePush() {
  try {
    await push.subscribe()
    toast.add({ title: 'Push auf diesem Gerät aktiviert', color: 'success', icon: 'i-lucide-bell-ring' })
  } catch (error) {
    showError(error, 'Push konnte nicht aktiviert werden.')
  }
}

async function disablePush() {
  try {
    await push.unsubscribe()
    toast.add({ title: 'Push auf diesem Gerät deaktiviert', color: 'success', icon: 'i-lucide-bell-off' })
  } catch (error) {
    showError(error)
  }
}

async function install() {
  const prompt = installPrompt.value
  if (!prompt) return
  await prompt.prompt()
  await prompt.userChoice
  installPrompt.value = null
}
</script>

<template>
  <div class="space-y-6">
    <h1 class="text-2xl font-bold text-highlighted">
      Profil
    </h1>

    <UCard
      title="Dein Name"
      description="Unter diesem Namen sehen dich die anderen in deinem Fanclub."
    >
      <DisplayNameForm
        :initial="profile?.display_name ?? ''"
        submit-label="Speichern"
        :save="saveName"
      />
    </UCard>

    <UCard
      title="Passwort"
      :description="hasPassword
        ? 'Du kannst dich mit Passwort oder per Code aus der E-Mail anmelden.'
        : 'Mit einem Passwort brauchst du beim Anmelden keinen Code aus der E-Mail. Der Code funktioniert trotzdem weiterhin.'"
    >
      <UForm
        v-if="!hasPassword || changingPassword"
        :schema="newPasswordSchema"
        :state="passwordState"
        class="space-y-4"
        @submit="savePassword"
      >
        <!-- Für Passwort-Manager: zu welchem Konto das Passwort gehört -->
        <UInput
          :model-value="user?.email ?? ''"
          type="email"
          autocomplete="username"
          readonly
          tabindex="-1"
          aria-hidden="true"
          class="hidden"
        />

        <UFormField
          name="password"
          :label="hasPassword ? 'Neues Passwort' : 'Passwort'"
          :help="`Mindestens ${PASSWORD_MIN_LENGTH} Zeichen.`"
        >
          <PasswordInput
            v-model="passwordState.password"
            autocomplete="new-password"
          />
        </UFormField>

        <div class="space-y-2">
          <UButton
            type="submit"
            label="Passwort speichern"
            size="lg"
            block
            loading-auto
          />
          <UButton
            v-if="changingPassword"
            label="Abbrechen"
            color="neutral"
            variant="ghost"
            size="lg"
            block
            @click="cancelPasswordChange"
          />
        </div>
      </UForm>

      <UButton
        v-else
        label="Passwort ändern"
        icon="i-lucide-key-round"
        color="neutral"
        variant="outline"
        block
        @click="changingPassword = true"
      />
    </UCard>

    <UCard
      title="Benachrichtigungen"
      description="Zum Beispiel wenn eine Anstoßzeit feststeht, du nachrückst oder dein Ticket da ist."
      :ui="{ body: 'space-y-5' }"
    >
      <USwitch
        :model-value="profile?.email_notifications ?? true"
        :loading="emailSaving"
        :disabled="emailSaving"
        label="E-Mail-Benachrichtigungen"
        description="An die Adresse, mit der du dich anmeldest."
        @update:model-value="toggleEmail"
      />

      <USeparator />

      <div class="space-y-3">
        <p class="text-sm font-medium text-highlighted">
          Push-Nachrichten auf diesem Gerät
        </p>

        <template v-if="push.supported.value">
          <template v-if="push.subscribed.value">
            <UAlert
              color="success"
              variant="subtle"
              icon="i-lucide-bell-ring"
              title="Push ist auf diesem Gerät aktiv."
            />
            <UButton
              label="Push deaktivieren"
              icon="i-lucide-bell-off"
              color="neutral"
              variant="outline"
              block
              loading-auto
              @click="disablePush"
            />
          </template>
          <UAlert
            v-else-if="push.permission.value === 'denied'"
            color="warning"
            variant="subtle"
            icon="i-lucide-bell-off"
            title="Benachrichtigungen sind blockiert."
            description="Erlaube sie in den Einstellungen deines Browsers für diese Seite und lade die Seite neu."
          />
          <UButton
            v-else
            label="Push auf diesem Gerät aktivieren"
            icon="i-lucide-bell-ring"
            block
            loading-auto
            @click="enablePush"
          />
        </template>

        <UAlert
          v-else-if="push.isIos.value && !push.isStandalone.value"
          color="info"
          variant="subtle"
          icon="i-lucide-smartphone"
          title="Auf dem iPhone erst die App installieren"
          description="Push-Nachrichten gibt es auf dem iPhone nur für installierte Apps. Öffne die Seite in Safari, tippe auf „Teilen“ und dann auf „Zum Home-Bildschirm“."
        />
        <p
          v-else
          class="text-sm text-muted"
        >
          Dein Browser unterstützt keine Push-Nachrichten. E-Mails bekommst du trotzdem.
        </p>
      </div>
    </UCard>

    <UCard
      v-if="!push.isStandalone.value"
      title="App installieren"
      description="Mit der App auf dem Home-Bildschirm bist du schneller bei deinen Fahrten und Tickets."
      :ui="{ body: 'space-y-3' }"
    >
      <UButton
        v-if="installPrompt"
        label="App installieren"
        icon="i-lucide-download"
        block
        @click="install"
      />
      <p
        v-else-if="push.isIos.value"
        class="text-sm text-highlighted"
      >
        In Safari auf „Teilen“ tippen und „Zum Home-Bildschirm“ wählen.
      </p>
      <p
        v-else
        class="text-sm text-highlighted"
      >
        Im Browser-Menü (⋮) „App installieren“ oder „Zum Startbildschirm hinzufügen“ wählen.
      </p>
    </UCard>
  </div>
</template>
