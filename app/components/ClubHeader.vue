<script setup lang="ts">
import type { ClubMembership } from '~/composables/useClubs'

const props = defineProps<{
  club: ClubMembership
  back?: { label: string, to: string }
}>()

const route = useRoute()

// Unterseiten des Fanclubs; die aktuelle Seite taucht im Menü nicht auf
const menuItems = computed(() => {
  const base = `/clubs/${props.club.id}`
  const isOrganizer = props.club.role === 'organizer'
  const items = [
    {
      label: 'Mitglieder',
      description: isOrganizer ? 'Verwalten und einladen' : 'Wer ist dabei?',
      icon: 'i-lucide-users',
      to: `${base}/members`
    },
    ...(isOrganizer
      ? [{ label: 'Einstellungen', description: 'Verein, PayPal, Fanclub löschen', icon: 'i-lucide-settings', to: `${base}/settings` }]
      : [])
  ]
  return items.filter(item => item.to !== route.path.replace(/\/$/, ''))
})
</script>

<template>
  <!--
    Menüzeile wie das Inhaltsverzeichnis der Nuxt-UI-Docs: klappt in der Seite auf und klebt beim
    Scrollen unter der Kopfzeile. Sie ist ein eigener Root-Knoten, damit sie direkt im Seiten-Container
    liegt; sticky wirkt nur innerhalb des Elternelements.
    Negative Ränder heben den Innenabstand des Containers auf (layouts/default.vue: px-4 lg:px-12,
    py-6 sm:py-10): oben, damit die Zeile auch ungescrollt direkt unter der Kopfzeile sitzt, seitlich,
    damit beim Scrollen am Rand kein Inhalt durchscheint. Die gestrichelte Linie geht auf dem Handy bis
    zum Bildschirmrand; ab lg steht der Container mittig, dort bleibt sie auf Inhaltsbreite.
  -->
  <div
    v-if="menuItems.length"
    class="sticky top-(--ui-header-height) z-10 -mx-4 -mt-6 border-b border-dashed border-default bg-default/75 px-4 backdrop-blur-sm sm:-mt-10 lg:-mx-12 lg:border-b-0 lg:px-12"
  >
    <UCollapsible class="lg:border-b lg:border-dashed lg:border-default">
      <UButton
        label="Menü"
        trailing-icon="i-lucide-chevron-down"
        color="neutral"
        variant="ghost"
        block
        class="group h-(--ui-header-height) px-0 hover:bg-transparent active:bg-transparent"
        :ui="{ trailingIcon: 'ms-auto transition-transform duration-200 group-data-[state=open]:rotate-180' }"
      />

      <template #content>
        <nav
          aria-label="Fanclub"
          class="pb-3"
        >
          <ULink
            v-for="item in menuItems"
            :key="item.to"
            :to="item.to"
            raw
            class="flex items-center gap-3 py-2.5"
          >
            <UIcon
              :name="item.icon"
              class="size-5 shrink-0 text-dimmed"
            />
            <span class="min-w-0 flex-1">
              <span class="block text-sm font-medium text-highlighted">{{ item.label }}</span>
              <span class="block text-sm text-muted">{{ item.description }}</span>
            </span>
            <UIcon
              name="i-lucide-chevron-right"
              class="size-4 shrink-0 text-dimmed"
            />
          </ULink>
        </nav>
      </template>
    </UCollapsible>
  </div>

  <div class="space-y-2">
    <UButton
      v-if="back"
      :to="back.to"
      :label="back.label"
      icon="i-lucide-arrow-left"
      color="neutral"
      variant="link"
      class="-ms-2.5"
    />
    <div class="flex items-start justify-between gap-3">
      <h1 class="text-2xl font-bold text-highlighted">
        {{ club.name }}
      </h1>
      <UBadge
        v-if="club.role === 'organizer'"
        :label="ROLE_LABELS.organizer"
        variant="subtle"
        class="mt-1.5 shrink-0"
      />
    </div>
  </div>
</template>
