import { serverSupabaseServiceRole } from '#supabase/server'

// Täglicher Job (Vercel Cron, siehe vercel.json). Vercel sendet "Authorization: Bearer <CRON_SECRET>";
// derselbe Wert steht serverseitig in runtimeConfig.cronSecret (NUXT_CRON_SECRET).

/** Vergleich in konstanter Zeit, damit das Secret nicht über Antwortzeiten erraten werden kann */
function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return diff === 0
}

export default defineEventHandler(async (event) => {
  const { cronSecret } = useRuntimeConfig(event)
  const header = getHeader(event, 'authorization') ?? ''
  if (!cronSecret || !safeEqual(header, `Bearer ${cronSecret}`)) {
    throw createError({ statusCode: 401, statusMessage: 'Unauthorized' })
  }

  const summary = await purgeExpiredTicketData(serverSupabaseServiceRole(event))
  console.info('Löschfrist', summary)
  return summary
})
