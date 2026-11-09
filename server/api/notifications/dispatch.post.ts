import { serverSupabaseServiceRole, serverSupabaseUser } from '#supabase/server'

// Die App stößt den Versand nach Aktionen an, die Benachrichtigungen auslösen. Verschickt wird nur,
// was DB-Trigger in den Postausgang geschrieben haben; der Aufruf selbst erzeugt nichts.
export default defineEventHandler(async (event) => {
  const user = await serverSupabaseUser(event)
  if (!user) {
    throw createError({ statusCode: 401, statusMessage: 'Unauthorized' })
  }

  return await dispatchNotifications(
    serverSupabaseServiceRole(event),
    notificationSiteUrl(getRequestURL(event).origin)
  )
})
