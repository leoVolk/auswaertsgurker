<script setup lang="ts">
import type { BadgeProps, DropdownMenuItem } from '@nuxt/ui'

// Kopf der Detailseiten (Fahrt, Ticketabfrage): Spiel und Anstoß in einer Zeile,
// Organisator-Aktionen im Menü statt als Buttons am Seitenende
defineProps<{
  backTo: string
  backLabel: string
  icon: string
  title: string
  badge?: { label: string, color: BadgeProps['color'] }
  matchday: number
  opponentName: string
  kickoffAt: string | null
  provisionalAt?: string | null
  actions?: DropdownMenuItem[][]
}>()
</script>

<template>
  <header class="space-y-1">
    <UButton
      :to="backTo"
      :label="backLabel"
      icon="i-lucide-arrow-left"
      color="neutral"
      variant="link"
      size="sm"
      class="-ms-2 max-w-full"
      :ui="{ label: 'truncate' }"
    />

    <div class="flex items-center gap-2.5">
      <UIcon
        :name="icon"
        class="size-6 shrink-0 text-primary"
      />
      <h1 class="min-w-0 truncate text-xl font-bold text-highlighted">
        {{ title }}
      </h1>
      <UBadge
        v-if="badge"
        :label="badge.label"
        :color="badge.color"
        variant="subtle"
        size="sm"
        class="shrink-0"
      />
      <UDropdownMenu
        v-if="actions?.length"
        :items="actions"
        :content="{ align: 'end' }"
      >
        <UButton
          icon="i-lucide-ellipsis-vertical"
          color="neutral"
          variant="ghost"
          aria-label="Weitere Aktionen"
          class="ms-auto shrink-0"
        />
      </UDropdownMenu>
    </div>

    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted">
      <span>{{ matchday }}. Spieltag bei {{ opponentName }}</span>
      <KickoffLabel
        :kickoff-at="kickoffAt"
        :provisional-at="provisionalAt"
      />
    </div>
  </header>
</template>
