<script setup lang="ts">
import { de } from '@nuxt/ui/locale'

useHead({
  htmlAttrs: { lang: 'de' },
  link: [{ rel: 'icon', href: '/favicon.ico' }],
  titleTemplate: title => (title ? `${title} · Auswärtsfahrt` : 'Auswärtsfahrt')
})

useSeoMeta({
  description: 'Auswärtsfahrten und Tickets für deinen Fanclub organisieren.',
  // Fanclub-Inhalte und Einladungslinks gehören nicht in Suchmaschinen
  robots: 'noindex, nofollow'
})
</script>

<template>
  <UApp :locale="de">
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </UApp>
</template>
