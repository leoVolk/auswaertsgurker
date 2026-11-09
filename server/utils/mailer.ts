import nodemailer from 'nodemailer'
import type { Transporter } from 'nodemailer'

let transporter: Transporter | null = null

/** SMTP-Versand (z. B. Strato); null, solange keine Zugangsdaten konfiguriert sind */
export function getMailer() {
  const { smtp } = useRuntimeConfig()
  if (!smtp.host || !smtp.user || !smtp.pass || !smtp.from) return null

  transporter ??= nodemailer.createTransport({
    host: smtp.host,
    port: Number(smtp.port),
    secure: Number(smtp.port) === 465,
    auth: { user: smtp.user, pass: smtp.pass },
    // Verbindung für mehrere Mails eines Versandlaufs wiederverwenden
    pool: true,
    maxConnections: 2
  })
  return { transporter, from: smtp.from }
}
