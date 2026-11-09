// Registriert den Service Worker (für Push) und merkt sich den Installations-Dialog von Chrome/Android
import type { BeforeInstallPromptEvent } from '~/composables/usePwa'

export default defineNuxtPlugin(() => {
  const installPrompt = useInstallPrompt()

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault()
    installPrompt.value = event as BeforeInstallPromptEvent
  })
  window.addEventListener('appinstalled', () => {
    installPrompt.value = null
  })

  if ('serviceWorker' in navigator) {
    onNuxtReady(() => {
      navigator.serviceWorker.register('/sw.js').catch((error) => {
        console.error('Service Worker konnte nicht registriert werden', error)
      })
    })
  }
})
