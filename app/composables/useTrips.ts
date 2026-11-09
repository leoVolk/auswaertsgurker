import type { AwayMatch } from '#shared/types/openligadb'
import type { Enums } from '~/types/database.types'

export type TransportMode = Enums<'transport_mode'>

export const TRANSPORT_MODES: Record<TransportMode, { label: string, icon: string }> = {
  bus: { label: 'Bus', icon: 'i-lucide-bus' },
  train: { label: 'Zug', icon: 'i-lucide-train-front' },
  car: { label: 'Auto', icon: 'i-lucide-car' }
}

export interface TripInput {
  transport: TransportMode
  title: string | null
  departureAt: string | null
  meetingPoint: string | null
  capacity: number | null
  priceCents: number | null
  registrationDeadline: string | null
  notes: string | null
}

export interface TripSummary {
  id: string
  matchId: number
  transport: TransportMode
  title: string | null
  departureAt: string | null
}

export interface TripDetail extends TripInput {
  id: string
  clubId: string
  awayGame: {
    matchId: number
    matchday: number
    opponentName: string
    kickoffAt: string | null
  }
}

/** Anzeigename einer Fahrt: eigener Titel oder das Verkehrsmittel */
export function tripLabel(trip: { title: string | null, transport: TransportMode }) {
  return trip.title ?? TRANSPORT_MODES[trip.transport].label
}

/** Alle Fahrten eines Fanclubs, gruppiert nach OpenLigaDB-Spiel. */
export async function useClubTrips(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: trips, error, refresh } = await useAsyncData(
    () => `club-trips-${toValue(clubId)}`,
    async (): Promise<TripSummary[]> => {
      const id = toValue(clubId)
      if (!isUuid(id)) return []

      const { data, error } = await supabase
        .from('trips')
        .select('id, transport, title, departure_at, away_game:away_games!inner(openligadb_match_id)')
        .eq('club_id', id)
        .order('departure_at', { nullsFirst: false })
      if (error) throw error

      return data.map(trip => ({
        id: trip.id,
        matchId: trip.away_game.openligadb_match_id,
        transport: trip.transport,
        title: trip.title,
        departureAt: trip.departure_at
      }))
    },
    { default: () => [] }
  )

  const tripsByMatch = computed(() => {
    const map = new Map<number, TripSummary[]>()
    for (const trip of trips.value) {
      map.set(trip.matchId, [...(map.get(trip.matchId) ?? []), trip])
    }
    return map
  })

  return { trips, tripsByMatch, error, refresh }
}

/** Eine einzelne Fahrt; `null`, wenn sie nicht existiert oder nicht sichtbar ist. */
export async function useTrip(tripId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: trip, error, refresh } = await useAsyncData(
    () => `trip-${toValue(tripId)}`,
    async (): Promise<TripDetail | null> => {
      const id = toValue(tripId)
      if (!isUuid(id)) return null

      const { data, error } = await supabase
        .from('trips')
        .select(`
          id, club_id, transport, title, departure_at, meeting_point, capacity, price_cents,
          registration_deadline, notes,
          away_game:away_games!inner(openligadb_match_id, matchday, opponent_name, kickoff_at)
        `)
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      if (!data) return null

      return {
        id: data.id,
        clubId: data.club_id,
        transport: data.transport,
        title: data.title,
        departureAt: data.departure_at,
        meetingPoint: data.meeting_point,
        capacity: data.capacity,
        priceCents: data.price_cents,
        registrationDeadline: data.registration_deadline,
        notes: data.notes,
        awayGame: {
          matchId: data.away_game.openligadb_match_id,
          matchday: data.away_game.matchday,
          opponentName: data.away_game.opponent_name,
          kickoffAt: data.away_game.kickoff_at
        }
      }
    }
  )

  return { trip, error, refresh }
}

function toRow(input: TripInput) {
  return {
    transport: input.transport,
    title: input.title,
    departure_at: input.departureAt,
    meeting_point: input.meetingPoint,
    capacity: input.capacity,
    price_cents: input.priceCents,
    registration_deadline: input.registrationDeadline,
    notes: input.notes
  }
}

export function useTripActions(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  /** Legt das Auswärtsspiel bei Bedarf an (bzw. aktualisiert dessen Spieldaten) und dann die Fahrt. */
  async function createTrip(match: AwayMatch, input: TripInput) {
    const { data: awayGameId, error: awayGameError } = await supabase.rpc('ensure_away_game', {
      p_club_id: toValue(clubId),
      p_openligadb_match_id: match.matchId,
      p_league_shortcut: match.leagueShortcut,
      p_season: match.season,
      p_matchday: match.matchday,
      p_opponent_name: match.opponentName,
      // null = Termin offen (Platzhalter nicht speichern). Die generierten Typen kennen
      // kein null für RPC-Parameter; weglassen geht nicht, sonst findet PostgREST die Funktion nicht.
      p_kickoff_at: match.kickoffAt as string
    })
    if (awayGameError) throw awayGameError

    const { data, error } = await supabase
      .from('trips')
      .insert({ ...toRow(input), club_id: toValue(clubId), away_game_id: awayGameId })
      .select('id')
      .single()
    if (error) throw error
    return data.id
  }

  async function updateTrip(tripId: string, input: TripInput) {
    const { error } = await supabase.from('trips').update(toRow(input)).eq('id', tripId)
    if (error) throw error
  }

  async function deleteTrip(tripId: string) {
    const { error } = await supabase.from('trips').delete().eq('id', tripId)
    if (error) throw error
  }

  return { createTrip, updateTrip, deleteTrip }
}
