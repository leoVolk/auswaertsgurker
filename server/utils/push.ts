// web-push 4 ist ein ES-Modul ohne Default-Export
import { sendNotification, setVapidDetails } from 'web-push'

let configured = false

/** Web-Push mit VAPID; null, solange keine Schlüssel konfiguriert sind */
export function getPush() {
  const config = useRuntimeConfig()
  const publicKey = config.public.vapidPublicKey
  const privateKey = config.vapidPrivateKey
  // VAPID verlangt eine Kontaktangabe (mailto: oder https-URL); sonst Absender der E-Mails nutzen
  const senderAddress = /[^\s<>]+@[^\s<>]+/.exec(config.smtp.from)?.[0]
  const subject = config.vapidSubject
    || (config.public.siteUrl.startsWith('https://') ? config.public.siteUrl : '')
    || (senderAddress ? `mailto:${senderAddress}` : '')
  if (!publicKey || !privateKey || !subject) return null

  if (!configured) {
    setVapidDetails(subject, publicKey, privateKey)
    configured = true
  }
  return { sendNotification }
}

/** Abo ist beim Push-Dienst abgelaufen oder abgemeldet und kann gelöscht werden */
export function isExpiredSubscription(error: unknown) {
  const statusCode = (error as { statusCode?: number } | null)?.statusCode
  return statusCode === 404 || statusCode === 410
}
