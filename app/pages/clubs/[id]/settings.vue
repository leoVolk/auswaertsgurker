<script setup lang="ts">
import type { FormSubmitEvent } from '@nuxt/ui'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const updateClub = useUpdateClub()
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer, refresh } = await useClub(clubId)

useHead({ title: 'Einstellungen' })

const state = reactive<{ name: string, league: LeagueShortcut, teamId: number | undefined }>({
  name: club.value?.name ?? '',
  league: club.value?.team?.league ?? 'bl1',
  teamId: club.value?.team?.teamId
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
      team: { league: event.data.league, teamId: team.teamId, name: team.name }
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
  </div>
</template>
