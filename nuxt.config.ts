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

  // Werte kommen zur Laufzeit aus NUXT_*-Umgebungsvariablen (siehe .env.example)
  runtimeConfig: {
    // Schützt /api/cron/*. Auf Vercel denselben Wert zusätzlich als CRON_SECRET hinterlegen,
    // damit Vercel ihn beim Cron-Aufruf mitsendet.
    cronSecret: '',
    // E-Mail-Benachrichtigungen (z. B. Strato: smtp.strato.de, Port 465)
    smtp: {
      host: '',
      port: 465,
      user: '',
      pass: '',
      from: ''
    },
    // Web-Push
    vapidPrivateKey: '',
    vapidSubject: '',
    public: {
      // Basis-URL für Links in E-Mails und Push, z. B. https://auswaertsfahrt.example
      siteUrl: '',
      vapidPublicKey: ''
    }
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
