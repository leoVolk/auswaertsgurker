<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const updateClub = useUpdateClub()
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer, refresh } = await useClub(clubId)

useHead({ title: 'Einstellungen' })

const state = reactive<{ name: string, league: LeagueShortcut, teamId: number | undefined, paypalMe: string }>({
  name: club.value?.name ?? '',
  league: club.value?.team?.league ?? 'bl1',
  teamId: club.value?.team?.teamId,
  paypalMe: club.value?.paypalMe ?? ''
})

// Vorschau des Links, wie Mitglieder ihn sehen
const paypalPreview = computed(() => {
  const name = extractPaypalMeName(state.paypalMe)
  return /^[A-Za-z0-9]{1,20}$/.test(name) ? `https://paypal.me/${name}` : null
})

const leagueItems = LEAGUES.map(league => ({ label: league.label, value: league.value }))

const { data: teams, status: teamsStatus, error: teamsError } = await useLeagueTeams(() => state.league)
const teamItems = computed(() => teams.value.map(team => ({ label: team.name, value: team.teamId })))

// Andere Liga: bisherige Vereinsauswahl passt nicht mehr
watch(() => state.league, () => {
  state.teamId = undefined
})

async function onSubmit(event: FormSubmitEvent<ClubSettingsForm>) {
  const team = teams.value.find(t => t.teamId === event.data.teamId)
  if (!team) return

  try {
    await updateClub(clubId.value, {
      name: event.data.name,
      team: { league: event.data.league, teamId: team.teamId, name: team.name },
      paypalMe: event.data.paypalMe || null
    })
    await refresh()
    toast.add({ title: 'Einstellungen gespeichert', color: 'success', icon: 'i-lucide-check' })
    await navigateTo(`/clubs/${clubId.value}`)
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UEmpty
    v-if="!club || !isOrganizer"
    icon="i-lucide-lock"
    title="Kein Zugriff"
    description="Nur Organisatoren können die Einstellungen eines Fanclubs ändern."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <ClubHeader
      :club="club"
      :back="{ label: 'Zurück zum Fanclub', to: `/clubs/${club.id}` }"
    />

    <UCard
      title="Einstellungen"
      description="Der Verein bestimmt, welche Auswärtsspiele angezeigt werden."
    >
      <UForm
        :schema="clubSettingsSchema"
        :state="state"
        class="space-y-4"
        @submit="onSubmit"
      >
        <UFormField
          name="name"
          label="Name des Fanclubs"
        >
          <UInput
            v-model="state.name"
            size="lg"
            class="w-full"
          />
        </UFormField>

        <UFormField
          name="league"
          label="Liga"
        >
          <USelect
            v-model="state.league"
            :items="leagueItems"
            size="lg"
            class="w-full"
          />
        </UFormField>

        <UFormField
          name="teamId"
          label="Verein"
          :error="teamsError ? 'Die Vereine konnten nicht geladen werden.' : undefined"
        >
          <USelect
            v-model="state.teamId"
            :items="teamItems"
            :loading="teamsStatus === 'pending'"
            placeholder="Verein auswählen"
            size="lg"
            class="w-full"
          />
        </UFormField>

        <UFormField
          name="paypalMe"
          label="PayPal.Me-Name"
          hint="Optional"
          help="Darüber bezahlen Mitglieder Fahrtkosten und Tickets. Du kannst auch den ganzen Link einfügen."
        >
          <UFieldGroup
            size="lg"
            class="w-full"
          >
            <UBadge
              label="paypal.me/"
              color="neutral"
              variant="outline"
            />
            <UInput
              v-model="state.paypalMe"
              placeholder="MeinFanclub"
              autocomplete="off"
              class="w-full"
            />
          </UFieldGroup>
          <ULink
            v-if="paypalPreview"
            :to="paypalPreview"
            target="_blank"
            class="mt-1.5 inline-block text-sm text-primary underline"
          >
            Link testen
          </ULink>
        </UFormField>

        <UButton
          type="submit"
          label="Speichern"
          size="lg"
          block
          loading-auto
        />
      </UForm>

      <template #footer>
        <OpenLigaDbAttribution />
      </template>
    </UCard>

    <ClubDeleteCard :club="club" />
  </div>
</template>
