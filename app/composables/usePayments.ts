import type { BadgeProps, DropdownMenuItem } from '@nuxt/ui'
import type { Enums } from '~/types/database.types'

export type PaymentStatus = Enums<'payment_status'>

export const PAYMENT_STATUS: Record<PaymentStatus, { label: string, color: BadgeProps['color'] }> = {
  open: { label: 'Zahlung offen', color: 'neutral' },
  reported: { label: 'Zahlung gemeldet', color: 'warning' },
  confirmed: { label: 'Bezahlt', color: 'success' },
  refunded: { label: 'Erstattet', color: 'info' }
}

/** Zusammengefasster Zahlungsstand mehrerer Posten aus Sicht des Mitglieds */
export function combinedPaymentStatus(statuses: PaymentStatus[]): PaymentStatus {
  if (statuses.includes('open')) return 'open'
  if (statuses.includes('reported')) return 'reported'
  if (statuses.length && statuses.every(status => status === 'refunded')) return 'refunded'
  return 'confirmed'
}

interface PaymentTargets {
  tripRegistrationIds?: string[]
  ticketRequestIds?: string[]
}

export function usePaymentActions() {
  const supabase = useSupabaseClient()

  /** Mitglied meldet eigene Zahlungen (open -> reported) */
  async function reportPayment(targets: PaymentTargets) {
    const { data, error } = await supabase.rpc('report_payment', {
      p_trip_registration_ids: targets.tripRegistrationIds ?? [],
      p_ticket_request_ids: targets.ticketRequestIds ?? []
    })
    if (error) throw error
    return data
  }

  /** Organisatoren: bestätigen, zurück auf offen oder erstatten */
  async function setPaymentStatus(status: Exclude<PaymentStatus, 'reported'>, targets: PaymentTargets) {
    const { data, error } = await supabase.rpc('set_payment_status', {
      p_status: status,
      p_trip_registration_ids: targets.tripRegistrationIds ?? [],
      p_ticket_request_ids: targets.ticketRequestIds ?? []
    })
    if (error) throw error
    return data
  }

  return { reportPayment, setPaymentStatus }
}

/** Menüeinträge für Organisatoren, passend zum aktuellen Zahlungsstatus */
export function paymentMenuItems(
  status: PaymentStatus,
  onSet: (status: Exclude<PaymentStatus, 'reported'>) => void
): DropdownMenuItem[] {
  const items: DropdownMenuItem[] = []
  if (status === 'open' || status === 'reported') {
    items.push({ label: 'Zahlung bestätigen', icon: 'i-lucide-badge-check', onSelect: () => onSet('confirmed') })
  }
  if (status === 'confirmed') {
    items.push({ label: 'Als erstattet markieren', icon: 'i-lucide-undo-2', onSelect: () => onSet('refunded') })
  }
  if (status === 'reported' || status === 'confirmed' || status === 'refunded') {
    items.push({ label: 'Zahlung auf offen setzen', icon: 'i-lucide-circle-dashed', onSelect: () => onSet('open') })
  }
  return items
}
