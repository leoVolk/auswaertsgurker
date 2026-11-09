<script setup lang="ts">
defineProps<{
  kickoffAt: string | null
  provisionalAt?: string | null
}>()
</script>

<template>
  <span
    v-if="kickoffAt"
    class="flex items-center gap-1.5"
  >
    <UIcon
      name="i-lucide-clock"
      class="size-4 shrink-0 text-dimmed"
    />
    {{ formatDateTime(kickoffAt) }}
  </span>
  <span
    v-else
    class="flex flex-wrap items-center gap-1.5"
  >
    <UBadge
      label="Termin offen"
      color="warning"
      variant="subtle"
      size="sm"
    />
    <span
      v-if="provisionalAt"
      class="text-muted"
    >
      Wochenende um den {{ formatDayMonth(provisionalAt) }}
    </span>
  </span>
</template>
