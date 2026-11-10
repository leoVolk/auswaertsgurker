import type { BadgeProps } from '@nuxt/ui'
import type { AwayMatch } from '#shared/types/openligadb'
import type { Enums } from '~/types/database.types'
import type { PaymentStatus } from './usePayments'

export type TicketStatus = Enums<'ticket_status'>
export type TicketDeliveryMethod = Enums<'ticket_delivery_method'>

export const TICKET_STATUS: Record<TicketStatus, { label: string, color: BadgeProps['color'] }> = {
  requested: { label: 'Angefragt', color: 'warning' },
  allocated: { label: 'Zugeteilt', color: 'success' },
  waitlist: { label: 'Warteliste', color: 'info' },
  rejected: { label: 'Abgelehnt', color: 'error' },
  cancelled: { label: 'Storniert', color: 'neutral' }
}

/** Anfragen, die beim Höchstwert pro Mitglied mitzählen */
export const ACTIVE_TICKET_STATUSES: TicketStatus[] = ['requested', 'allocated', 'waitlist']

export interface TicketCategory {
  id: string
  name: string
  priceCents: number
  quota: number | null
}

export interface TicketRound {
  id: string
  clubId: string
  requestDeadline: string | null
  maxTicketsPerMember: number | null
  membershipNumberRequired: boolean
  downloadRequiresPayment: boolean
  notes: string | null
  closedAt: string | null
  /** Mitgliedsnummern und PDFs nach Ablauf der Löschfrist entfernt */
  personalDataPurged: boolean
  awayGame: {
    matchId: number
    matchday: number
    opponentName: string
    kickoffAt: string | null
  }
  categories: TicketCategory[]
}

export interface TicketRequest {
  id: string
  categoryId: string
  requestedBy: string
  requesterName: string
  holderName: string
  holderMembershipNumber: string | null
  status: TicketStatus
  deliveryMethod: TicketDeliveryMethod | null
  pickupLocation: string | null
  pickupAt: string | null
  ticketFilePath: string | null
  paymentStatus: PaymentStatus
}

export interface TicketRoundSummary {
  id: string
  matchId: number
  requestDeadline: string | null
  closedAt: string | null
  /** Status der eigenen Anfragen */
  myStatuses: TicketStatus[]
  /** Offene Anfragen aller Mitglieder (nur für Organisatoren aussagekräftig) */
  openCount: number
}

export interface TicketRoundInput {
  requestDeadline: string | null
  maxTicketsPerMember: number | null
  membershipNumberRequired: boolean
  downloadRequiresPayment: boolean
  notes: string | null
  categories: { id?: string, name: string, priceCents: number, quota: number | null }[]
}

export function isTicketRoundOpen(round: { closedAt: string | null, requestDeadline: string | null }) {
  return !round.closedAt && (!round.requestDeadline || Date.now() <= new Date(round.requestDeadline).getTime())
}

/**
 * Blendet überholte Stornierungen aus (Liste nach Anfragezeitpunkt sortiert): Hat dieselbe Person
 * für denselben Inhaber wieder angefragt, verschwindet die stornierte Anfrage, sonst bleibt nur die
 * letzte. Sichtbar bleiben Stornierungen, um die sich noch jemand kümmern muss (Zahlung, PDF).
 */
export function withoutSupersededCancellations(requests: TicketRequest[]) {
  const key = (r: TicketRequest) => `${r.requestedBy}:${r.holderName.trim().replace(/\s+/g, ' ').toLocaleLowerCase('de-DE')}`
  const needsAttention = (r: TicketRequest) =>
    r.ticketFilePath !== null || (r.paymentStatus !== 'open' && r.paymentStatus !== 'refunded')

  const requestedAgain = new Set(requests.filter(r => r.status !== 'cancelled').map(key))
  const lastCancelled = new Map(requests.filter(r => r.status === 'cancelled').map(r => [key(r), r.id]))

  return requests.filter(r =>
    r.status !== 'cancelled'
    || needsAttention(r)
    || (!requestedAgain.has(key(r)) && lastCancelled.get(key(r)) === r.id)
  )
}

/** Alle Ticketabfragen eines Fanclubs für die Übersicht. */
export async function useClubTicketRounds(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()

  const { data: rounds, error, refresh } = await useAsyncData(
    () => `club-ticket-rounds-${toValue(clubId)}`,
    async (): Promise<TicketRoundSummary[]> => {
      const id = toValue(clubId)
      if (!isUuid(id)) return []

      // Mitglieder sehen per RLS nur ihre eigenen Anfragen, Organisatoren alle
      const [roundsResult, requestsResult] = await Promise.all([
        supabase
          .from('ticket_rounds')
          .select('id, request_deadline, closed_at, away_game:away_games!inner(openligadb_match_id)')
          .eq('club_id', id),
        supabase
          .from('ticket_requests')
          .select('round_id, status, requested_by')
          .eq('club_id', id)
      ])
      if (roundsResult.error) throw roundsResult.error
      if (requestsResult.error) throw requestsResult.error

      return roundsResult.data.map((round) => {
        const requests = requestsResult.data.filter(r => r.round_id === round.id)
        return {
          id: round.id,
          matchId: round.away_game.openligadb_match_id,
          requestDeadline: round.request_deadline,
          closedAt: round.closed_at,
          myStatuses: requests.filter(r => r.requested_by === userId.value).map(r => r.status),
          openCount: requests.filter(r => r.status === 'requested').length
        }
      })
    },
    { default: () => [] }
  )

  const roundsByMatch = computed(() => new Map(rounds.value.map(round => [round.matchId, round])))

  return { rounds, roundsByMatch, error, refresh }
}

// Spalten und Umwandlung gemeinsam für die Ticketseite und „Meine Tickets“
const TICKET_ROUND_COLUMNS = `
  id, club_id, request_deadline, max_tickets_per_member, membership_number_required,
  download_requires_payment, notes, closed_at,
  away_game:away_games!inner(openligadb_match_id, matchday, opponent_name, kickoff_at, personal_data_purged_at),
  categories:ticket_categories(id, name, price_cents, quota, sort_order)
`

const TICKET_REQUEST_COLUMNS = `
  id, category_id, requested_by, holder_name, holder_membership_number, status,
  delivery_method, pickup_location, pickup_at, ticket_file_path, payment_status,
  requester:profiles!inner(display_name)
`

interface TicketRoundRow {
  id: string
  club_id: string
  request_deadline: string | null
  max_tickets_per_member: number | null
  membership_number_required: boolean
  download_requires_payment: boolean
  notes: string | null
  closed_at: string | null
  away_game: {
    openligadb_match_id: number
    matchday: number
    opponent_name: string
    kickoff_at: string | null
    personal_data_purged_at: string | null
  }
  categories: { id: string, name: string, price_cents: number, quota: number | null, sort_order: number }[]
}

interface TicketRequestRow {
  id: string
  category_id: string
  requested_by: string
  holder_name: string
  holder_membership_number: string | null
  status: TicketStatus
  delivery_method: TicketDeliveryMethod | null
  pickup_location: string | null
  pickup_at: string | null
  ticket_file_path: string | null
  payment_status: PaymentStatus
  requester: { display_name: string | null }
}

function toTicketRound(row: TicketRoundRow): TicketRound {
  return {
    id: row.id,
    clubId: row.club_id,
    requestDeadline: row.request_deadline,
    maxTicketsPerMember: row.max_tickets_per_member,
    membershipNumberRequired: row.membership_number_required,
    downloadRequiresPayment: row.download_requires_payment,
    notes: row.notes,
    closedAt: row.closed_at,
    personalDataPurged: row.away_game.personal_data_purged_at !== null,
    awayGame: {
      matchId: row.away_game.openligadb_match_id,
      matchday: row.away_game.matchday,
      opponentName: row.away_game.opponent_name,
      kickoffAt: row.away_game.kickoff_at
    },
    categories: [...row.categories]
      .sort((a, b) => a.sort_order - b.sort_order)
      .map(c => ({ id: c.id, name: c.name, priceCents: c.price_cents, quota: c.quota }))
  }
}

function toTicketRequest(row: TicketRequestRow): TicketRequest {
  return {
    id: row.id,
    categoryId: row.category_id,
    requestedBy: row.requested_by,
    requesterName: row.requester.display_name ?? 'Ohne Namen',
    holderName: row.holder_name,
    holderMembershipNumber: row.holder_membership_number,
    status: row.status,
    deliveryMethod: row.delivery_method,
    pickupLocation: row.pickup_location,
    pickupAt: row.pickup_at,
    ticketFilePath: row.ticket_file_path,
    paymentStatus: row.payment_status
  }
}

/** Eine Ticketabfrage samt Kategorien; `null`, wenn sie nicht existiert oder nicht sichtbar ist. */
export async function useTicketRound(roundId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: round, error, refresh } = await useAsyncData(
    () => `ticket-round-${toValue(roundId)}`,
    async (): Promise<TicketRound | null> => {
      const id = toValue(roundId)
      if (!isUuid(id)) return null

      const { data, error } = await supabase
        .from('ticket_rounds')
        .select(TICKET_ROUND_COLUMNS)
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data ? toTicketRound(data) : null
    }
  )

  return { round, error, refresh }
}

/** Anfragen einer Ticketabfrage: für Mitglieder nur die eigenen, für Organisatoren alle (RLS). */
export async function useTicketRequests(roundId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()

  const { data: requests, error, refresh } = await useAsyncData(
    () => `ticket-requests-${toValue(roundId)}`,
    async (): Promise<TicketRequest[]> => {
      const id = toValue(roundId)
      if (!isUuid(id)) return []

      const { data, error } = await supabase
        .from('ticket_requests')
        .select(TICKET_REQUEST_COLUMNS)
        .eq('round_id', id)
        .order('created_at')
      if (error) throw error
      return data.map(toTicketRequest)
    },
    { default: () => [] }
  )

  return { requests, error, refresh }
}

export interface MyTicketGroup {
  round: TicketRound
  club: { id: string, name: string, paypalMe: string | null }
  /** Eigene Anfragen dieser Abfrage */
  requests: TicketRequest[]
  /** Spiel liegt mehr als einen Tag zurück oder die Ticketdaten sind schon gelöscht */
  past: boolean
}

const PAST_AFTER_KICKOFF_MS = 24 * 60 * 60 * 1000

/**
 * Alle eigenen Ticketanfragen über alle Fanclubs, gruppiert nach Ticketabfrage (= Spiel).
 * Kommende Spiele nach Anstoß aufsteigend (offene Termine zuletzt), vergangene absteigend.
 */
export async function useMyTickets() {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()

  const { data: groups, error, refresh } = await useAsyncData(
    'my-tickets',
    async (): Promise<MyTicketGroup[]> => {
      if (!userId.value) return []

      // Organisatoren dürfen alle Anfragen lesen, deshalb ausdrücklich auf die eigenen filtern
      const { data, error } = await supabase
        .from('ticket_rounds')
        .select(`${TICKET_ROUND_COLUMNS}, club:clubs!inner(id, name, paypal_me), my_requests:ticket_requests!inner(${TICKET_REQUEST_COLUMNS})`)
        .eq('my_requests.requested_by', userId.value)
        .order('created_at', { referencedTable: 'my_requests' })
      if (error) throw error

      const now = Date.now()
      const groups = data
        .map((row): MyTicketGroup => {
          const round = toTicketRound(row)
          const kickoff = round.awayGame.kickoffAt ? new Date(round.awayGame.kickoffAt).getTime() : null
          return {
            round,
            club: { id: row.club.id, name: row.club.name, paypalMe: row.club.paypal_me },
            requests: row.my_requests.map(toTicketRequest),
            past: round.personalDataPurged || (kickoff !== null && kickoff + PAST_AFTER_KICKOFF_MS < now)
          }
        })
        // Nur Stornierte ohne offene Erstattung braucht hier niemand mehr
        .filter(group => group.requests.some(r => r.status !== 'cancelled' || r.paymentStatus === 'confirmed'))

      const kickoffOf = (group: MyTicketGroup) =>
        group.round.awayGame.kickoffAt ? new Date(group.round.awayGame.kickoffAt).getTime() : Number.POSITIVE_INFINITY
      return groups.sort((a, b) => {
        if (a.past !== b.past) return a.past ? 1 : -1
        const diff = a.past ? kickoffOf(b) - kickoffOf(a) : kickoffOf(a) - kickoffOf(b)
        return diff || a.round.awayGame.matchday - b.round.awayGame.matchday
      })
    },
    { default: () => [] }
  )

  return { groups, error, refresh }
}

export function useTicketRequestActions() {
  const supabase = useSupabaseClient()
  const dispatch = useNotificationDispatch()

  // Die generierten Typen kennen kein null für RPC-Parameter; null wird trotzdem korrekt übertragen
  async function requestTicket(categoryId: string, holderName: string, membershipNumber: string | null) {
    const { data, error } = await supabase.rpc('request_ticket', {
      p_category_id: categoryId,
      p_holder_name: holderName,
      p_membership_number: membershipNumber as string
    })
    if (error) throw error
    return data
  }

  async function updateHolder(requestId: string, holderName: string, membershipNumber: string | null) {
    const { error } = await supabase.rpc('update_ticket_request_holder', {
      p_request_id: requestId,
      p_holder_name: holderName,
      p_membership_number: membershipNumber as string
    })
    if (error) throw error
  }

  async function cancelRequest(requestId: string) {
    const { error } = await supabase.rpc('cancel_ticket_request', { p_request_id: requestId })
    if (error) throw error
  }

  async function setStatus(requestId: string, status: Exclude<TicketStatus, 'cancelled'>) {
    const { error } = await supabase.rpc('set_ticket_request_status', {
      p_request_id: requestId,
      p_status: status
    })
    if (error) throw error
    dispatch()
  }

  async function autoAllocate(categoryId: string) {
    const { data, error } = await supabase.rpc('auto_allocate_tickets', { p_category_id: categoryId })
    if (error) throw error
    dispatch()
    return data[0] ?? { allocated: 0, waitlisted: 0 }
  }

  return { requestTicket, updateHolder, cancelRequest, setStatus, autoAllocate }
}

export function useTicketRoundActions(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()
  const ensureAwayGame = useEnsureAwayGame()
  const dispatch = useNotificationDispatch()

  function categoryRow(category: TicketRoundInput['categories'][number], index: number) {
    return {
      name: category.name,
      price_cents: category.priceCents,
      quota: category.quota,
      sort_order: index
    }
  }

  async function createRound(match: AwayMatch, input: TicketRoundInput) {
    const club = toValue(clubId)
    const awayGameId = await ensureAwayGame(club, match)

    const { data: round, error } = await supabase
      .from('ticket_rounds')
      .insert({
        club_id: club,
        away_game_id: awayGameId,
        request_deadline: input.requestDeadline,
        max_tickets_per_member: input.maxTicketsPerMember,
        membership_number_required: input.membershipNumberRequired,
        download_requires_payment: input.downloadRequiresPayment,
        notes: input.notes
      })
      .select('id')
      .single()
    if (error) {
      if (error.code === '23505') throw new UserError('Für dieses Spiel gibt es schon eine Ticketabfrage.')
      throw error
    }

    const { error: categoriesError } = await supabase
      .from('ticket_categories')
      .insert(input.categories.map((category, index) => ({
        ...categoryRow(category, index),
        round_id: round.id,
        club_id: club
      })))
    if (categoriesError) {
      // Keine Abfrage ohne Kategorien zurücklassen
      await supabase.from('ticket_rounds').delete().eq('id', round.id)
      throw categoriesError
    }

    dispatch()
    return round.id
  }

  async function updateRound(roundId: string, input: TicketRoundInput, previous: TicketCategory[]) {
    const club = toValue(clubId)

    const { error } = await supabase
      .from('ticket_rounds')
      .update({
        request_deadline: input.requestDeadline,
        max_tickets_per_member: input.maxTicketsPerMember,
        membership_number_required: input.membershipNumberRequired,
        download_requires_payment: input.downloadRequiresPayment,
        notes: input.notes
      })
      .eq('id', roundId)
    if (error) throw error

    const keptIds = new Set(input.categories.map(c => c.id).filter(Boolean))
    for (const category of previous.filter(c => !keptIds.has(c.id))) {
      const { error } = await supabase.from('ticket_categories').delete().eq('id', category.id)
      if (error?.code === '23503') {
        throw new UserError(`„${category.name}“ hat schon Anfragen und kann nicht entfernt werden.`)
      }
      if (error) throw error
    }

    for (const [index, category] of input.categories.entries()) {
      const row = categoryRow(category, index)
      const { error } = category.id
        ? await supabase.from('ticket_categories').update(row).eq('id', category.id)
        : await supabase.from('ticket_categories').insert({ ...row, round_id: roundId, club_id: club })
      if (error) throw error
    }
  }

  async function setClosed(roundId: string, closed: boolean) {
    const { error } = await supabase
      .from('ticket_rounds')
      .update({ closed_at: closed ? new Date().toISOString() : null })
      .eq('id', roundId)
    if (error) throw error
  }

  async function deleteRound(roundId: string) {
    // Ticket-PDFs zuerst aus dem Storage entfernen; nach dem Löschen der Anfragen ginge das nicht mehr
    const { data: files, error: filesError } = await supabase
      .from('ticket_requests')
      .select('ticket_file_path')
      .eq('round_id', roundId)
      .not('ticket_file_path', 'is', null)
    if (filesError) throw filesError
    const paths = files.flatMap(file => (file.ticket_file_path ? [file.ticket_file_path] : []))
    if (paths.length) {
      const { error: storageError } = await supabase.storage.from(TICKET_FILES_BUCKET).remove(paths)
      if (storageError) throw storageError
    }

    const { error } = await supabase.from('ticket_rounds').delete().eq('id', roundId)
    if (error) throw error
  }

  return { createRound, updateRound, setClosed, deleteRound }
}

// ---------------------------------------------------------------------------
// Hinterlegung
// ---------------------------------------------------------------------------

export const TICKET_FILE_MAX_BYTES = 5 * 1024 * 1024

export const TICKET_DELIVERY: Record<TicketDeliveryMethod, { label: string, icon: string }> = {
  digital: { label: 'PDF', icon: 'i-lucide-file-text' },
  pickup: { label: 'Abholung', icon: 'i-lucide-map-pin' },
  box_office: { label: 'Gästekasse', icon: 'i-lucide-store' }
}

/** Prüft eine Ticketdatei vor dem Upload; liefert eine Fehlermeldung oder null. */
export function ticketFileProblem(file: File) {
  if (file.type !== 'application/pdf' && !file.name.toLowerCase().endsWith('.pdf')) {
    return `„${file.name}“ ist keine PDF-Datei.`
  }
  if (file.size > TICKET_FILE_MAX_BYTES) {
    return `„${file.name}“ ist größer als 5 MB.`
  }
  return null
}

export function useTicketDeliveryActions(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()
  const dispatch = useNotificationDispatch()
  const bucket = () => supabase.storage.from(TICKET_FILES_BUCKET)

  async function uploadTicketFile(requestId: string, file: File) {
    const problem = ticketFileProblem(file)
    if (problem) throw new UserError(problem)

    const path = `${toValue(clubId)}/${requestId}.pdf`
    const { error: uploadError } = await bucket().upload(path, file, {
      upsert: true,
      contentType: 'application/pdf'
    })
    if (uploadError) throw uploadError

    const { error } = await supabase.rpc('attach_ticket_file', { p_request_id: requestId })
    if (error) throw error
    dispatch()
  }

  async function removeTicketFile(requestId: string) {
    const { data: path, error } = await supabase.rpc('detach_ticket_file', { p_request_id: requestId })
    if (error) throw error
    if (path) {
      const { error: storageError } = await bucket().remove([path])
      if (storageError) throw storageError
    }
  }

  async function setDelivery(
    requestIds: string[],
    method: TicketDeliveryMethod,
    pickupLocation: string | null,
    pickupAt: string | null
  ) {
    // Die generierten Typen kennen kein null für RPC-Parameter; null wird trotzdem korrekt übertragen
    const { data: detachedPaths, error } = await supabase.rpc('set_ticket_delivery', {
      p_request_ids: requestIds,
      p_method: method,
      p_pickup_location: pickupLocation as string,
      p_pickup_at: pickupAt as string
    })
    if (error) throw error
    dispatch()
    if (detachedPaths.length) {
      const { error: storageError } = await bucket().remove(detachedPaths)
      if (storageError) throw storageError
    }
  }

  return { uploadTicketFile, removeTicketFile, setDelivery }
}

/** Öffnet ein Ticket-PDF über einen kurzlebigen signierten Link (Rechte prüft die Storage-Policy). */
export function useOpenTicketFile() {
  const supabase = useSupabaseClient()

  return async (path: string, holderName: string) => {
    const fileName = `Ticket-${holderName.replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-+|-+$/g, '')}.pdf`
    const { data, error } = await supabase.storage
      .from(TICKET_FILES_BUCKET)
      .createSignedUrl(path, 60, { download: fileName })
    if (error) throw error
    // Gleicher Tab statt Pop-up, das blockieren In-App-Browser nach async-Aufrufen gern
    window.location.assign(data.signedUrl)
  }
}
