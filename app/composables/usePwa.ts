/** Chrome/Android-Event für „App installieren“ (nicht in den Standard-DOM-Typen) */
export interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

export function useInstallPrompt() {
  return useState<BeforeInstallPromptEvent | null>('pwa-install-prompt', () => null)
}

function urlBase64ToUint8Array(base64: string) {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4)
  const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'))
  return Uint8Array.from(raw, char => char.charCodeAt(0))
}

/** Push-Benachrichtigungen für dieses Gerät verwalten */
export function usePushNotifications() {
  const supabase = useSupabaseClient()
  const { vapidPublicKey } = useRuntimeConfig().public

  const supported = ref(false)
  const permission = ref<NotificationPermission>('default')
  const subscribed = ref(false)
  const isIos = ref(false)
  const isStandalone = ref(false)

  async function currentSubscription() {
    const registration = await navigator.serviceWorker.getRegistration()
    return (await registration?.pushManager.getSubscription()) ?? null
  }

  async function refresh() {
    isIos.value = /iphone|ipad|ipod/i.test(navigator.userAgent)
    isStandalone.value = window.matchMedia('(display-mode: standalone)').matches
      || (navigator as Navigator & { standalone?: boolean }).standalone === true
    supported.value = Boolean(vapidPublicKey)
      && 'serviceWorker' in navigator
      && 'PushManager' in window
      && 'Notification' in window
    if (!supported.value) return

    permission.value = Notification.permission
    subscribed.value = (await currentSubscription()) !== null
  }

  async function subscribe() {
    permission.value = await Notification.requestPermission()
    if (permission.value !== 'granted') {
      throw new UserError('Benachrichtigungen sind blockiert. Erlaube sie in den Einstellungen deines Browsers.')
    }

    const registration = await navigator.serviceWorker.register('/sw.js')
    await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
    })

    const { endpoint, keys } = subscription.toJSON()
    if (!endpoint || !keys?.p256dh || !keys.auth) {
      throw new UserError('Dein Browser hat kein gültiges Push-Abo geliefert.')
    }
    const { error } = await supabase.rpc('save_push_subscription', {
      p_endpoint: endpoint,
      p_p256dh: keys.p256dh,
      p_auth: keys.auth,
      p_user_agent: navigator.userAgent
    })
    if (error) {
      await subscription.unsubscribe()
      throw error
    }
    subscribed.value = true
  }

  async function unsubscribe() {
    const subscription = await currentSubscription()
    if (subscription) {
      await supabase.rpc('delete_push_subscription', { p_endpoint: subscription.endpoint })
      await subscription.unsubscribe()
    }
    subscribed.value = false
  }

  onMounted(refresh)

  return { supported, permission, subscribed, isIos, isStandalone, subscribe, unsubscribe }
}

let dispatchTimer: ReturnType<typeof setTimeout> | undefined

/**
 * Stößt den Versand offener Benachrichtigungen an (nach Aktionen, die welche auslösen).
 * Mehrere Aktionen kurz hintereinander, z. B. ein Sammel-Upload, führen zu einem Aufruf.
 */
export function useNotificationDispatch() {
  return () => {
    clearTimeout(dispatchTimer)
    dispatchTimer = setTimeout(() => {
      $fetch('/api/notifications/dispatch', { method: 'POST' }).catch((error) => {
        console.warn('Benachrichtigungen konnten nicht verschickt werden', error)
      })
    }, 1500)
  }
}
