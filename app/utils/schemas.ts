import { z } from 'zod'
import { Constants } from '~/types/database.types'

export const emailSchema = z.object({
  email: z.string().trim().pipe(z.email('Bitte gib eine gültige E-Mail-Adresse ein.'))
})
export type EmailForm = z.output<typeof emailSchema>

// Muss zur Einstellung „Email OTP Length“ im Supabase-Projekt passen
export const OTP_LENGTH = 8

// UPinInput liefert die Ziffern einzeln; für Supabase werden sie zu einem String
export const otpSchema = z.object({
  code: z.array(z.number())
    .transform(digits => digits.join(''))
    .pipe(z.string().regex(new RegExp(`^\\d{${OTP_LENGTH}}$`), `Gib alle ${OTP_LENGTH} Ziffern aus der E-Mail ein.`))
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
  teamId: z.number('Bitte wähle euren Verein.'),
  // Name oder eingefügter Link; leer = kein PayPal-Link
  paypalMe: z.string()
    .transform(extractPaypalMeName)
    .refine(name => name === '' || /^[A-Za-z0-9]{1,20}$/.test(name), 'Bitte gib den PayPal.Me-Namen ein (nur Buchstaben und Ziffern, z. B. MeinFanclub).')
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

export const ticketRoundFormSchema = z.object({
  // Wert aus <input type="datetime-local">, leer = keine Frist
  requestDeadline: z.string(),
  maxTicketsPerMember: z.number().int('Bitte gib eine ganze Zahl ein.')
    .min(1, 'Mindestens 1 Ticket.')
    .max(20, 'Höchstens 20 Tickets.')
    .nullish(),
  membershipNumberRequired: z.boolean(),
  downloadRequiresPayment: z.boolean(),
  notes: z.string().trim().max(2000, 'Höchstens 2000 Zeichen.'),
  categories: z.array(z.object({
    id: z.string().optional(),
    name: z.string().trim().min(1, 'Bitte gib einen Namen ein.').max(60, 'Höchstens 60 Zeichen.'),
    price: z.number('Bitte gib einen Preis ein.')
      .min(0, 'Der Preis kann nicht negativ sein.')
      .max(1000, 'Höchstens 1.000 €.'),
    quota: z.number().int('Bitte gib eine ganze Zahl ein.')
      .min(0, 'Das Kontingent kann nicht negativ sein.')
      .max(10000, 'Höchstens 10.000 Tickets.')
      .nullish()
  })).min(1, 'Lege mindestens eine Kategorie an.')
})
export type TicketRoundForm = z.output<typeof ticketRoundFormSchema>

export function ticketHolderSchema(membershipNumberRequired: boolean) {
  const number = z.string().trim().max(40, 'Höchstens 40 Zeichen.')
  return z.object({
    holderName: z.string().trim()
      .min(2, 'Bitte gib den Namen des Inhabers ein.')
      .max(80, 'Höchstens 80 Zeichen.'),
    membershipNumber: membershipNumberRequired
      ? number.min(1, 'Für diese Abfrage brauchst du die Mitgliedsnummer.')
      : number
  })
}
export type TicketHolderForm = z.output<ReturnType<typeof ticketHolderSchema>>

export const ticketDeliverySchema = z.object({
  method: z.enum(Constants.public.Enums.ticket_delivery_method, 'Bitte wähle, wie die Tickets hinterlegt werden.'),
  pickupLocation: z.string().trim().max(200, 'Höchstens 200 Zeichen.'),
  // Wert aus <input type="datetime-local">, leer = keine feste Zeit
  pickupAt: z.string()
}).refine(
  delivery => delivery.method !== 'pickup' || delivery.pickupLocation.length > 0,
  { message: 'Bitte gib an, wo die Tickets abgeholt werden.', path: ['pickupLocation'] }
)
export type TicketDeliveryForm = z.output<typeof ticketDeliverySchema>

export function isUuid(value: string) {
  return z.uuid().safeParse(value).success
}
