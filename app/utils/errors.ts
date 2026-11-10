const DEFAULT_MESSAGE = 'Das hat leider nicht geklappt. Versuch es bitte noch einmal.'

// Fehlercodes von Supabase Auth, die Nutzer selbst beheben können
const AUTH_MESSAGES: Record<string, string> = {
  over_email_send_rate_limit: 'Es wurden gerade zu viele E-Mails verschickt. Warte bitte ein paar Minuten.',
  over_request_rate_limit: 'Zu viele Versuche. Warte bitte einen Moment.',
  otp_expired: 'Der Code ist falsch oder abgelaufen.',
  email_address_invalid: 'Diese E-Mail-Adresse wird nicht akzeptiert.',
  signup_disabled: 'Neue Anmeldungen sind gerade deaktiviert.',
  validation_failed: 'Bitte prüfe deine Eingabe.',
  invalid_credentials: 'E-Mail-Adresse oder Passwort stimmen nicht. Du kannst dich auch per Code anmelden.',
  weak_password: 'Dieses Passwort ist zu unsicher. Wähle bitte ein längeres.',
  same_password: 'Das ist bereits dein aktuelles Passwort.',
  // Nur wenn „Secure password change“ in Supabase aktiv ist und der Login älter als 24 Stunden ist
  reauthentication_needed: 'Aus Sicherheitsgründen musst du dich dafür neu anmelden. Melde dich ab, per Code wieder an und ändere das Passwort direkt danach.'
}

/** Fehler mit einer Meldung, die direkt in der Oberfläche angezeigt werden darf */
export class UserError extends Error {}

/**
 * Übersetzt Fehler von Supabase in eine deutsche Meldung.
 * Meldungen aus eigenen Datenbankfunktionen (`raise exception`, Code P0001) sind bereits deutsch.
 */
export function errorMessage(error: unknown, fallback = DEFAULT_MESSAGE): string {
  if (error instanceof UserError) {
    return error.message
  }
  if (error && typeof error === 'object') {
    const { code, message } = error as { code?: unknown, message?: unknown }

    if (code === 'P0001' && typeof message === 'string') {
      return message
    }
    if (typeof code === 'string' && AUTH_MESSAGES[code]) {
      return AUTH_MESSAGES[code]
    }
  }
  return fallback
}

/** Nur interne Pfade zulassen, damit Redirect-Parameter nicht auf fremde Seiten führen. */
export function safeRedirect(path: unknown, fallback = '/'): string {
  if (typeof path !== 'string' || !path.startsWith('/') || path.startsWith('//') || path.startsWith('/\\')) {
    return fallback
  }
  return path
}
