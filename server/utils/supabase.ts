import type { serverSupabaseServiceRole } from '#supabase/server'
import type { Database } from '../../app/types/database.types'

/** Supabase-Client mit Secret Key (umgeht RLS) – nur in Server-Jobs verwenden */
export type ServiceClient = ReturnType<typeof serverSupabaseServiceRole<Database>>
