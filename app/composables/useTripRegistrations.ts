import type { BadgeProps } from '@nuxt/ui'
import type { Enums } from '~/types/database.types'
import type { PaymentStatus } from './usePayments'

export type RegistrationStatus = Enums<'registration_status'>

export const REGISTRATION_STATUS: Record<RegistrationStatus, { label: string, color: BadgeProps['color'] }> = {
  requested: { label: 'Angefragt', color: 'warning' },
  confirmed: { label: 'Bestätigt', color: 'success' },
  waitlist: { label: 'Warteliste', color: 'info' },
  cancelled: { label: 'Abgesagt', color: 'neutral' }
}

export interface TripStats {
  takenSeats: number
  waitlistCount: number
  myRegistrationId: string | null
  myStatus: RegistrationStatus | null
  myWaitlistPosition: number | null
  myPaymentStatus: PaymentStatus | null
}

export interface TripParticipant {
  id: string
  userId: string
  displayName: string
  status: RegistrationStatus
  paymentStatus: PaymentStatus
}

/** Belegung aller Fahrten eines Fanclubs und der eigene Anmeldestatus. */
export async function useTripStats(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: stats, error, refresh } = await useAsyncData(
    () => `trip-stats-${toValue(clubId)}`,
    async () => {
      const map = new Map<string, TripStats>()
      const id = toValue(clubId)
      if (!isUuid(id)) return map

      const { data, error } = await supabase.rpc('get_trip_stats', { p_club_id: id })
      if (error) throw error

      // Die generierten Typen kennen kein null bei Rückgabespalten
      for (const row of data) {
        map.set(row.trip_id, {
          takenSeats: row.taken_seats,
          waitlistCount: row.waitlist_count,
          myRegistrationId: row.my_registration_id ?? null,
          myStatus: row.my_status ?? null,
          myWaitlistPosition: row.my_waitlist_position ?? null,
          myPaymentStatus: row.my_payment_status ?? null
        })
      }
      return map
    },
    { default: () => new Map<string, TripStats>() }
  )

  return { stats, error, refresh }
}

/** Alle Anmeldungen einer Fahrt (nur für Organisatoren lesbar). */
export async function useTripParticipants(tripId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: participants, error, refresh } = await useAsyncData(
    () => `trip-participants-${toValue(tripId)}`,
    async (): Promise<TripParticipant[]> => {
      const id = toValue(tripId)
      if (!isUuid(id)) return []

      const { data, error } = await supabase
        .from('trip_registrations')
        .select('id, user_id, status, payment_status, profile:profiles!inner(display_name)')
        .eq('trip_id', id)
        // Reihenfolge der Warteliste
        .order('status_changed_at')
        .order('created_at')
      if (error) throw error

      return data.map(r => ({
        id: r.id,
        userId: r.user_id,
        displayName: r.profile.display_name ?? 'Ohne Namen',
        status: r.status,
        paymentStatus: r.payment_status
      }))
    },
    { default: () => [] }
  )

  return { participants, error, refresh }
}

export function useTripRegistrationActions() {
  const supabase = useSupabaseClient()

  async function register(tripId: string) {
    const { data, error } = await supabase.rpc('register_for_trip', { p_trip_id: tripId })
    if (error) throw error
    return data
  }

  async function cancel(registrationId: string) {
    const { error } = await supabase.rpc('cancel_trip_registration', { p_registration_id: registrationId })
    if (error) throw error
  }

  async function confirm(registrationId: string) {
    const { error } = await supabase.rpc('confirm_trip_registration', { p_registration_id: registrationId })
    if (error) throw error
  }

  async function confirmAll(tripId: string) {
    const { data, error } = await supabase.rpc('confirm_all_trip_registrations', { p_trip_id: tripId })
    if (error) throw error
    return data
  }

  return { register, cancel, confirm, confirmAll }
}

/** Ob Anmeldungen (noch) möglich sind, und falls nicht, warum. */
export function registrationClosedReason(trip: { registrationDeadline: string | null, departureAt: string | null }) {
  const now = Date.now()
  if (trip.departureAt && now >= new Date(trip.departureAt).getTime()) return 'Die Fahrt hat schon begonnen.'
  if (trip.registrationDeadline && now > new Date(trip.registrationDeadline).getTime()) return 'Der Anmeldeschluss ist vorbei.'
  return null
}
