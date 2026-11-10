import type { Tables } from '../../app/types/database.types'
import type { ServiceClient } from './supabase'

type Notification = Tables<'notifications'>

const BATCH_SIZE = 25
// Vercel-Funktionen haben ein Zeitlimit; Rest holt der nächste Aufruf bzw. der tägliche Cron
const TIME_BUDGET_MS = 20_000

export interface DispatchSummary {
  sent: number
  failed: number
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
}

interface Message {
  title: string
  lines: string[]
  link: string
}

/** Mehrere Benachrichtigungen gleicher Art zum selben Ziel werden zu einer Nachricht */
function composeMessage(group: Notification[], siteUrl: string): Message {
  const first = group[0]!
  return {
    title: group.length > 1 ? `${first.title} (${group.length})` : first.title,
    lines: group.map(n => n.body),
    link: `${siteUrl}${first.url}`
  }
}

function emailContent(message: Message, clubName: string | undefined, siteUrl: string) {
  const footer = `Du bekommst diese E-Mail als Mitglied${clubName ? ` von ${clubName}` : ''} bei Auswärtsgurker. `
    + `E-Mail-Benachrichtigungen kannst du in deinem Profil abbestellen: ${siteUrl}/profile`

  const text = [message.title, '', ...message.lines, '', `In der App öffnen: ${message.link}`, '', '--', footer].join('\n')

  const html = `<!doctype html><html lang="de"><body style="margin:0;padding:24px;background:#f8fafc;font-family:Arial,Helvetica,sans-serif;color:#0f172a">
<div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:12px;padding:24px">
<h1 style="margin:0 0 16px;font-size:20px">${escapeHtml(message.title)}</h1>
${message.lines.map(line => `<p style="margin:0 0 12px;line-height:1.5">${escapeHtml(line)}</p>`).join('\n')}
<p style="margin:24px 0"><a href="${escapeHtml(message.link)}" style="display:inline-block;background:#0084d1;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:bold">In der App öffnen</a></p>
<p style="margin:24px 0 0;font-size:12px;color:#64748b;line-height:1.5">${escapeHtml(footer)}</p>
</div></body></html>`

  return { text, html }
}

/**
 * Verschickt offene Benachrichtigungen aus dem Postausgang per E-Mail und Push.
 * Gilt als zugestellt, wenn die E-Mail rausging (bzw. keine gewünscht ist); Push ist ein Zusatz.
 */
export async function dispatchNotifications(supabase: ServiceClient, siteUrl: string): Promise<DispatchSummary> {
  const summary: DispatchSummary = { sent: 0, failed: 0 }
  const mailer = getMailer()
  const push = getPush()
  const startedAt = Date.now()

  while (Date.now() - startedAt < TIME_BUDGET_MS) {
    const { data: claimed, error } = await supabase.rpc('claim_notifications', { p_limit: BATCH_SIZE })
    if (error) throw error
    if (!claimed.length) break

    const userIds = [...new Set(claimed.map(n => n.user_id))]
    const clubIds = [...new Set(claimed.flatMap(n => (n.club_id ? [n.club_id] : [])))]

    const [recipientsResult, subscriptionsResult, clubsResult] = await Promise.all([
      supabase.rpc('notification_recipients', { p_user_ids: userIds }),
      supabase.from('push_subscriptions').select('id, user_id, endpoint, p256dh, auth').in('user_id', userIds),
      supabase.from('clubs').select('id, name').in('id', clubIds)
    ])
    if (recipientsResult.error) throw recipientsResult.error
    if (subscriptionsResult.error) throw subscriptionsResult.error
    if (clubsResult.error) throw clubsResult.error

    const recipients = new Map(recipientsResult.data.map(r => [r.user_id, r]))
    const clubNames = new Map(clubsResult.data.map(c => [c.id, c.name]))

    const groups = new Map<string, Notification[]>()
    for (const notification of claimed) {
      const key = `${notification.user_id}|${notification.kind}|${notification.url}`
      groups.set(key, [...(groups.get(key) ?? []), notification])
    }

    for (const group of groups.values()) {
      const first = group[0]!
      const ids = group.map(n => n.id)
      const message = composeMessage(group, siteUrl)
      const recipient = recipients.get(first.user_id)

      // E-Mail
      let emailError: string | null = null
      if (recipient?.email && recipient.email_notifications) {
        if (!mailer) {
          emailError = 'SMTP ist nicht konfiguriert'
        } else {
          const clubName = first.club_id ? clubNames.get(first.club_id) : undefined
          const content = emailContent(message, clubName, siteUrl)
          try {
            await mailer.transporter.sendMail({
              from: mailer.from,
              to: recipient.email,
              subject: clubName ? `${message.title} · ${clubName}` : message.title,
              text: content.text,
              html: content.html
            })
          } catch (sendError) {
            emailError = sendError instanceof Error ? sendError.message : String(sendError)
          }
        }
      }

      // Push an alle Geräte; abgelaufene Abos aufräumen
      if (push) {
        const payload = JSON.stringify({
          title: message.title,
          body: message.lines.join(' ').slice(0, 240),
          url: first.url
        })
        for (const subscription of subscriptionsResult.data.filter(s => s.user_id === first.user_id)) {
          try {
            await push.sendNotification(
              { endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } },
              payload,
              { TTL: 60 * 60 * 24 }
            )
          } catch (pushError) {
            if (isExpiredSubscription(pushError)) {
              await supabase.from('push_subscriptions').delete().eq('id', subscription.id)
            } else {
              console.error('Push fehlgeschlagen', subscription.endpoint, pushError)
            }
          }
        }
      }

      const { error: completeError } = await supabase.rpc('complete_notifications', {
        p_ids: ids,
        p_success: emailError === null,
        // Die generierten Typen kennen kein null für RPC-Parameter
        p_error: emailError as string
      })
      if (completeError) throw completeError

      if (emailError === null) summary.sent += group.length
      else summary.failed += group.length
    }
  }

  return summary
}

/** Basis-URL für Links in Benachrichtigungen */
export function notificationSiteUrl(fallbackOrigin: string) {
  const { siteUrl } = useRuntimeConfig().public
  return (siteUrl || fallbackOrigin).replace(/\/$/, '')
}
