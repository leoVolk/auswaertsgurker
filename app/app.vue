<script setup lang="ts">
import { de } from '@nuxt/ui/locale'

useHead({
  htmlAttrs: { lang: 'de' },
  link: [
    { rel: 'icon', type: 'image/svg+xml', href: '/icons/icon.svg' },
    { rel: 'icon', type: 'image/png', sizes: '192x192', href: '/icons/icon-192.png' },
    { rel: 'apple-touch-icon', href: '/icons/apple-touch-icon.png' },
    { rel: 'manifest', href: '/manifest.webmanifest' }
  ],
  meta: [
    { name: 'theme-color', content: '#0084d1' },
    { name: 'apple-mobile-web-app-title', content: 'Auswärtsfahrt' },
    { name: 'mobile-web-app-capable', content: 'yes' }
  ],
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
