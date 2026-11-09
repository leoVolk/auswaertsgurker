import type { BadgeProps } from '@nuxt/ui'
import type { AwayMatch } from '#shared/types/openligadb'
import type { Enums } from '~/types/database.types'

export type TicketStatus = Enums<'ticket_status'>

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
  notes: string | null
  closedAt: string | null
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
  notes: string | null
  categories: { id?: string, name: string, priceCents: number, quota: number | null }[]
}

export function isTicketRoundOpen(round: { closedAt: string | null, requestDeadline: string | null }) {
  return !round.closedAt && (!round.requestDeadline || Date.now() <= new Date(round.requestDeadline).getTime())
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
        .select(`
          id, club_id, request_deadline, max_tickets_per_member, membership_number_required, notes, closed_at,
          away_game:away_games!inner(openligadb_match_id, matchday, opponent_name, kickoff_at),
          categories:ticket_categories(id, name, price_cents, quota, sort_order)
        `)
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      if (!data) return null

      return {
        id: data.id,
        clubId: data.club_id,
        requestDeadline: data.request_deadline,
        maxTicketsPerMember: data.max_tickets_per_member,
        membershipNumberRequired: data.membership_number_required,
        notes: data.notes,
        closedAt: data.closed_at,
        awayGame: {
          matchId: data.away_game.openligadb_match_id,
          matchday: data.away_game.matchday,
          opponentName: data.away_game.opponent_name,
          kickoffAt: data.away_game.kickoff_at
        },
        categories: [...data.categories]
          .sort((a, b) => a.sort_order - b.sort_order)
          .map(c => ({ id: c.id, name: c.name, priceCents: c.price_cents, quota: c.quota }))
      }
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
        .select(`
          id, category_id, requested_by, holder_name, holder_membership_number, status,
          requester:profiles!inner(display_name)
        `)
        .eq('round_id', id)
        .order('created_at')
      if (error) throw error

      return data.map(r => ({
        id: r.id,
        categoryId: r.category_id,
        requestedBy: r.requested_by,
        requesterName: r.requester.display_name ?? 'Ohne Namen',
        holderName: r.holder_name,
        holderMembershipNumber: r.holder_membership_number,
        status: r.status
      }))
    },
    { default: () => [] }
  )

  return { requests, error, refresh }
}

export function useTicketRequestActions() {
  const supabase = useSupabaseClient()

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
  }

  async function autoAllocate(categoryId: string) {
    const { data, error } = await supabase.rpc('auto_allocate_tickets', { p_category_id: categoryId })
    if (error) throw error
    return data[0] ?? { allocated: 0, waitlisted: 0 }
  }

  return { requestTicket, updateHolder, cancelRequest, setStatus, autoAllocate }
}

export function useTicketRoundActions(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()
  const ensureAwayGame = useEnsureAwayGame()

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
    const { error } = await supabase.from('ticket_rounds').delete().eq('id', roundId)
    if (error) throw error
  }

  return { createRound, updateRound, setClosed, deleteRound }
}
