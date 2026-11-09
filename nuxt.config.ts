// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  modules: [
    '@nuxt/eslint',
    '@nuxt/ui',
    '@nuxtjs/supabase'
  ],

  devtools: {
    enabled: true
  },

  css: ['~/assets/css/main.css'],

  runtimeConfig: {
    // Nur serverseitig, gesetzt über NUXT_CRON_SECRET; schützt /api/cron/*.
    // Auf Vercel denselben Wert zusätzlich als CRON_SECRET hinterlegen, damit Vercel ihn mitsendet.
    cronSecret: ''
  },

  compatibilityDate: '2026-06-30',

  eslint: {
    config: {
      stylistic: {
        commaDangle: 'never',
        braceStyle: '1tbs'
      }
    }
  },

  supabase: {
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      // Einladungslinks müssen ohne Login erreichbar sein
      exclude: ['/join/*'],
      // Nach dem Login zur ursprünglich aufgerufenen Seite zurückkehren
      saveRedirectToCookie: true
    }
  }
})
