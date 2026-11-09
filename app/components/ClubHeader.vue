<script setup lang="ts">
import type { ClubMembership } from '~/composables/useClubs'

defineProps<{
  club: ClubMembership
  back?: { label: string, to: string }
}>()
</script>

<template>
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
