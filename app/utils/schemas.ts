import { z } from 'zod'
import { Constants } from '~/types/database.types'

export const emailSchema = z.object({
  email: z.string().trim().pipe(z.email('Bitte gib eine gültige E-Mail-Adresse ein.'))
})
export type EmailForm = z.output<typeof emailSchema>

// Die Code-Länge ist im Supabase-Projekt einstellbar (6–10 Ziffern)
export const otpSchema = z.object({
  code: z.string().trim().regex(/^\d{6,10}$/, 'Gib den Code aus der E-Mail ein (nur Ziffern).')
})
export type OtpForm = z.output<typeof otpSchema>

export const displayNameSchema = z.object({
  displayName: z.string().trim()
    .min(2, 'Dein Name braucht mindestens 2 Zeichen.')
    .max(40, 'Dein Name darf höchstens 40 Zeichen lang sein.')
})
export type DisplayNameForm = z.output<typeof displayNameSchema>

export const clubNameSchema = z.object({
  name: z.string().trim()
    .min(2, 'Der Name braucht mindestens 2 Zeichen.')
    .max(80, 'Der Name darf höchstens 80 Zeichen lang sein.')
})
export type ClubNameForm = z.output<typeof clubNameSchema>

export const clubSettingsSchema = z.object({
  name: clubNameSchema.shape.name,
  league: z.enum(LEAGUE_SHORTCUTS, 'Bitte wähle eine Liga.'),
  teamId: z.number('Bitte wähle euren Verein.')
})
export type ClubSettingsForm = z.output<typeof clubSettingsSchema>

export const tripFormSchema = z.object({
  transport: z.enum(Constants.public.Enums.transport_mode, 'Bitte wähle ein Verkehrsmittel.'),
  title: z.string().trim().max(80, 'Höchstens 80 Zeichen.'),
  // Werte aus <input type="datetime-local">, leer = noch offen
  departureAt: z.string(),
  meetingPoint: z.string().trim().max(200, 'Höchstens 200 Zeichen.'),
  capacity: z.number().int('Bitte gib eine ganze Zahl ein.')
    .min(1, 'Mindestens 1 Platz.')
    .max(1000, 'Höchstens 1000 Plätze.')
    .nullish(),
  price: z.number()
    .min(0, 'Der Preis kann nicht negativ sein.')
    .max(1000, 'Höchstens 1.000 €.')
    .nullish(),
  registrationDeadline: z.string(),
  notes: z.string().trim().max(2000, 'Höchstens 2000 Zeichen.')
}).refine(
  trip => !trip.registrationDeadline || !trip.departureAt || trip.registrationDeadline <= trip.departureAt,
  { message: 'Der Anmeldeschluss muss vor der Abfahrt liegen.', path: ['registrationDeadline'] }
)
export type TripForm = z.output<typeof tripFormSchema>

export function isUuid(value: string) {
  return z.uuid().safeParse(value).success
}
