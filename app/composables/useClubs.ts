import type { Enums, Tables } from '~/types/database.types'

export type ClubRole = Enums<'club_role'>

export interface ClubTeam {
  league: LeagueShortcut
  teamId: number
  name: string
}

export interface ClubMembership {
  id: string
  name: string
  role: ClubRole
  team: ClubTeam | null
  /** PayPal.Me-Name des Fanclubs */
  paypalMe: string | null
}

export const ROLE_LABELS: Record<ClubRole, string> = {
  organizer: 'Organisator',
  member: 'Mitglied'
}

const CLUB_COLUMNS = 'id, name, league_shortcut, team_id, team_name, paypal_me'

type ClubRow = Pick<Tables<'clubs'>, 'id' | 'name' | 'league_shortcut' | 'team_id' | 'team_name' | 'paypal_me'>

function toMembership(club: ClubRow, role: ClubRole): ClubMembership {
  const team = isLeagueShortcut(club.league_shortcut) && club.team_id && club.team_name
    ? { league: club.league_shortcut, teamId: club.team_id, name: club.team_name }
    : null
  return { id: club.id, name: club.name, role, team, paypalMe: club.paypal_me }
}

/** Alle Fanclubs, in denen der angemeldete User Mitglied ist. */
export async function useMyClubs() {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()

  const { data: clubs, error, refresh } = await useAsyncData(
    'my-clubs',
    async (): Promise<ClubMembership[]> => {
      if (!userId.value) return []

      const { data, error } = await supabase
        .from('club_members')
        .select(`role, club:clubs!inner(${CLUB_COLUMNS})`)
        .eq('user_id', userId.value)
        .order('joined_at')
      if (error) throw error

      return data.map(m => toMembership(m.club, m.role))
    },
    { default: () => [] }
  )

  return { clubs, error, refresh }
}

/** Ein einzelner Fanclub samt eigener Rolle; `null`, wenn man kein Mitglied ist. */
export async function useClub(clubId: MaybeRefOrGetter<string>) {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()

  const { data: club, error, refresh } = await useAsyncData(
    () => `club-${toValue(clubId)}`,
    async (): Promise<ClubMembership | null> => {
      const id = toValue(clubId)
      if (!userId.value || !isUuid(id)) return null

      const { data, error } = await supabase
        .from('club_members')
        .select(`role, club:clubs!inner(${CLUB_COLUMNS})`)
        .eq('club_id', id)
        .eq('user_id', userId.value)
        .maybeSingle()
      if (error) throw error

      return data ? toMembership(data.club, data.role) : null
    }
  )

  const isOrganizer = computed(() => club.value?.role === 'organizer')

  return { club, isOrganizer, error, refresh }
}

export function useCreateClub() {
  const supabase = useSupabaseClient()

  return async (name: string) => {
    const { data, error } = await supabase.rpc('create_club', { p_name: name })
    if (error) throw error
    return data
  }
}

export function useUpdateClub() {
  const supabase = useSupabaseClient()

  return async (clubId: string, input: { name: string, team: ClubTeam, paypalMe: string | null }) => {
    const { error } = await supabase
      .from('clubs')
      .update({
        name: input.name,
        league_shortcut: input.team.league,
        team_id: input.team.teamId,
        team_name: input.team.name,
        paypal_me: input.paypalMe
      })
      .eq('id', clubId)
    if (error) throw error
  }
}

export interface ClubDeletionSummary {
  members: number
  trips: number
  ticketRounds: number
  /** Bestätigte, nicht erstattete Zahlungen für kommende Spiele */
  openPayments: number
  ticketFiles: number
}

/** Fanclub endgültig löschen (Organisatoren) oder verlassen (Mitglieder) */
export function useClubMembershipEnd() {
  const supabase = useSupabaseClient()
  const userId = useCurrentUserId()
  const dispatch = useNotificationDispatch()

  async function fetchDeletionSummary(clubId: string): Promise<ClubDeletionSummary | null> {
    const { data, error } = await supabase.rpc('club_deletion_summary', { p_club_id: clubId })
    if (error) throw error
    const row = data[0]
    return row
      ? {
          members: row.members,
          trips: row.trips,
          ticketRounds: row.ticket_rounds,
          openPayments: row.open_payments,
          ticketFiles: row.ticket_files
        }
      : null
  }

  async function deleteClub(clubId: string) {
    // Ticket-PDFs zuerst über die Storage-API löschen; nach dem Löschen fehlen die Verweise
    const { data: files, error: filesError } = await supabase
      .from('ticket_requests')
      .select('ticket_file_path')
      .eq('club_id', clubId)
      .not('ticket_file_path', 'is', null)
    if (filesError) throw filesError

    const paths = files.flatMap(file => (file.ticket_file_path ? [file.ticket_file_path] : []))
    for (let i = 0; i < paths.length; i += 100) {
      const { error } = await supabase.storage.from(TICKET_FILES_BUCKET).remove(paths.slice(i, i + 100))
      if (error) throw error
    }

    const { error, count } = await supabase.from('clubs').delete({ count: 'exact' }).eq('id', clubId)
    if (error) throw error
    if (!count) throw new UserError('Der Fanclub konnte nicht gelöscht werden. Das dürfen nur Organisatoren.')
  }

  async function leaveClub(clubId: string) {
    if (!userId.value) throw new UserError('Du bist nicht angemeldet.')
    const { error, count } = await supabase
      .from('club_members')
      .delete({ count: 'exact' })
      .eq('club_id', clubId)
      .eq('user_id', userId.value)
    if (error) throw error
    if (!count) throw new UserError('Du bist kein Mitglied dieses Fanclubs.')
    // Freie Plätze lassen die Warteliste nachrücken
    dispatch()
  }

  return { fetchDeletionSummary, deleteClub, leaveClub }
}
