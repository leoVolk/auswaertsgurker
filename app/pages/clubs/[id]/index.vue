<script setup lang="ts">
const route = useRoute()
const clubId = computed(() => String(route.params.id))

const { club, isOrganizer } = await useClub(clubId)
const { matches, error: matchesError } = await useAwayMatches(() => club.value?.team)
const { tripsByMatch } = await useClubTrips(clubId)

useHead({ title: () => club.value?.name ?? 'Fanclub' })
</script>

<template>
  <UEmpty
    v-if="!club"
    icon="i-lucide-search-x"
    title="Fanclub nicht gefunden"
    description="Entweder stimmt der Link nicht oder du bist kein Mitglied dieses Fanclubs."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <ClubHeader :club="club" />

    <section
      v-if="club.team"
      class="space-y-3"
    >
      <div>
        <h2 class="text-lg font-semibold text-highlighted">
          Nächste Auswärtsspiele
        </h2>
        <p class="text-sm text-muted">
          {{ club.team.name }} · {{ leagueLabel(club.team.league) }}
        </p>
      </div>

      <UAlert
        v-if="matchesError"
        color="error"
        variant="subtle"
        icon="i-lucide-circle-alert"
        title="Der Spielplan konnte nicht geladen werden."
        description="OpenLigaDB ist gerade nicht erreichbar. Versuch es später noch einmal."
      />

      <UEmpty
        v-else-if="!matches.length"
        icon="i-lucide-calendar-x"
        title="Keine Auswärtsspiele mehr"
        description="In dieser Saison stehen keine Auswärtsspiele mehr an."
      />

      <AwayGameCard
        v-for="match in matches"
        :key="match.matchId"
        :club-id="club.id"
        :match="match"
        :trips="tripsByMatch.get(match.matchId) ?? []"
        :is-organizer="isOrganizer"
      />

      <OpenLigaDbAttribution />
    </section>

    <UEmpty
      v-else-if="isOrganizer"
      icon="i-lucide-shield"
      title="Welchen Verein begleitet ihr?"
      description="Wähle euren Verein aus, dann erscheinen hier die Auswärtsspiele."
      :actions="[{ label: 'Verein auswählen', to: `/clubs/${club.id}/settings` }]"
    />

    <UEmpty
      v-else
      icon="i-lucide-shield"
      title="Noch kein Verein hinterlegt"
      description="Sobald die Organisatoren euren Verein ausgewählt haben, erscheinen hier die Auswärtsspiele."
    />

    <div class="grid gap-2">
      <UButton
        :to="`/clubs/${club.id}/members`"
        :label="isOrganizer ? 'Mitglieder verwalten und einladen' : 'Mitglieder ansehen'"
        icon="i-lucide-users"
        trailing-icon="i-lucide-chevron-right"
        color="neutral"
        variant="outline"
        size="lg"
        block
        :ui="{ trailingIcon: 'ms-auto' }"
      />
      <UButton
        v-if="isOrganizer"
        :to="`/clubs/${club.id}/settings`"
        label="Einstellungen"
        icon="i-lucide-settings"
        trailing-icon="i-lucide-chevron-right"
        color="neutral"
        variant="outline"
        size="lg"
        block
        :ui="{ trailingIcon: 'ms-auto' }"
      />
    </div>
  </div>
</template>
