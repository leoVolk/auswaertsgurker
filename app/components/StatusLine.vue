<script setup lang="ts">
import type { ChipProps } from '@nuxt/ui'

// Ruhige Statusanzeige (Farbpunkt + Text) statt farbiger Hinweisboxen
defineProps<{
  color: ChipProps['color']
  title: string
  description?: string
}>()
</script>

<template>
  <div class="flex gap-2.5 text-sm">
    <!-- Punkt mittig zur ersten Textzeile (Zeilenhöhe von text-sm) -->
    <span class="flex h-5 shrink-0 items-center">
      <UChip
        standalone
        inset
        :color="color"
      />
    </span>
    <div class="min-w-0">
      <p class="font-medium text-highlighted">
        {{ title }}
      </p>
      <p
        v-if="description"
        class="text-muted"
      >
        {{ description }}
      </p>
    </div>
  </div>
</template>
