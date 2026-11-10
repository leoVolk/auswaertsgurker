// Service Worker: zeigt Push-Benachrichtigungen an und öffnet beim Antippen die passende Seite.
// Kein Offline-Cache: Die App braucht für Fahrten und Tickets ohnehin aktuelle Daten.

self.addEventListener('install', () => {
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('push', (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch {
    data = { body: event.data ? event.data.text() : '' }
  }

  event.waitUntil(
    self.registration.showNotification(data.title || 'Auswärtsgurker', {
      body: data.body || '',
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      lang: 'de',
      data: { url: data.url || '/' }
    })
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin).href

  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    for (const client of windows) {
      try {
        await client.navigate(url)
        return client.focus()
      } catch {
        // Fenster lässt sich nicht steuern, neues öffnen
      }
    }
    return self.clients.openWindow(url)
  })())
})
