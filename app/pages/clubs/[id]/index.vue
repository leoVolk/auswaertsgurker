<script setup lang="ts">
import type { AccordionItem } from '@nuxt/ui'
import type { AwayMatch } from '#shared/types/openligadb'

const route = useRoute()
const clubId = computed(() => String(route.params.id))

const { club, isOrganizer } = await useClub(clubId)
const { matches, error: matchesError } = await useAwayMatches(() => club.value?.team)
const { tripsByMatch } = await useClubTrips(clubId)
const { stats } = await useTripStats(clubId)
const { roundsByMatch } = await useClubTicketRounds(clubId)

useHead({ title: () => club.value?.name ?? 'Fanclub' })

// Nicht terminierte Spiele kommen ins Accordion, damit die Liste kurz bleibt.
// Ausnahme: Für das Spiel gibt es schon eine Fahrt oder Ticketabfrage, dann bleibt es sichtbar.
function isPlanned(match: AwayMatch) {
  return tripsByMatch.value.has(match.matchId) || roundsByMatch.value.has(match.matchId)
}
const listedMatches = computed(() => matches.value.filter(m => m.kickoffAt || isPlanned(m)))
const unscheduledMatches = computed(() => matches.value.filter(m => !m.kickoffAt && !isPlanned(m)))

const unscheduledItems = computed<AccordionItem[]>(() => [{
  label: unscheduledMatches.value.length === 1
    ? '1 Spiel mit offenem Termin'
    : `${unscheduledMatches.value.length} Spiele mit offenem Termin`,
  icon: 'i-lucide-calendar-clock'
}])
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
        v-for="match in listedMatches"
        :key="match.matchId"
        :club-id="club.id"
        :match="match"
        :trips="tripsByMatch.get(match.matchId) ?? []"
        :stats="stats"
        :ticket-round="roundsByMatch.get(match.matchId)"
        :is-organizer="isOrganizer"
      />

      <!-- Sind alle kommenden Spiele noch offen, gleich aufgeklappt -->
      <UAccordion
        v-if="unscheduledMatches.length"
        :items="unscheduledItems"
        :default-value="listedMatches.length ? undefined : '0'"
        :ui="{ trigger: 'text-base', body: 'space-y-3' }"
      >
        <template #body>
          <AwayGameCard
            v-for="match in unscheduledMatches"
            :key="match.matchId"
            :club-id="club.id"
            :match="match"
            :trips="[]"
            :stats="stats"
            :is-organizer="isOrganizer"
          />
        </template>
      </UAccordion>

      <OpenLigaDbAttribution />
    </section>

    <UEmpty
      v-else-if="isOrganizer"
      icon="i-lucide-shield"
      title="Noch kein Verein ausgewählt"
      description="Wähle euren Verein aus, dann erscheinen hier die Auswärtsspiele."
      :actions="[{ label: 'Verein auswählen', to: `/clubs/${club.id}/settings` }]"
    />

    <UEmpty
      v-else
      icon="i-lucide-shield"
      title="Noch kein Verein ausgewählt"
      description="Die Auswärtsspiele erscheinen hier, wenn ein Organisator den Verein ausgewählt hat."
    />
  </div>
</template>
