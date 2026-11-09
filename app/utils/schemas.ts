import { z } from 'zod'

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

export function isUuid(value: string) {
  return z.uuid().safeParse(value).success
}
