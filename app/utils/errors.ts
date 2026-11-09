const DEFAULT_MESSAGE = 'Das hat leider nicht geklappt. Versuch es bitte noch einmal.'

// Fehlercodes von Supabase Auth, die Nutzer selbst beheben können
const AUTH_MESSAGES: Record<string, string> = {
  over_email_send_rate_limit: 'Es wurden gerade zu viele E-Mails verschickt. Warte bitte ein paar Minuten.',
  over_request_rate_limit: 'Zu viele Versuche. Warte bitte einen Moment.',
  otp_expired: 'Der Code ist falsch oder abgelaufen.',
  email_address_invalid: 'Diese E-Mail-Adresse wird nicht akzeptiert.',
  signup_disabled: 'Neue Anmeldungen sind gerade deaktiviert.',
  validation_failed: 'Bitte prüfe deine Eingabe.'
}

/**
 * Übersetzt Fehler von Supabase in eine deutsche Meldung.
 * Meldungen aus eigenen Datenbankfunktionen (`raise exception`, Code P0001) sind bereits deutsch.
 */
export function errorMessage(error: unknown, fallback = DEFAULT_MESSAGE): string {
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
