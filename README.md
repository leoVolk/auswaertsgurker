# Auswärtsfahrt

Web-App für Fußball-Fanclubs: Organisatoren planen Auswärtsfahrten (Bus, Zug, Auto) und verteilen
Tickets aus dem Fanclub-Kontingent. Mitglieder treten per Einladungslink bei, melden sich zu Fahrten
an, fragen Tickets an und bezahlen per PayPal.Me-Link des Fanclubs. Gebaut für das Handy.

**Stack:** Nuxt 4, Nuxt UI v4, Tailwind CSS v4, Supabase (Postgres, Auth, Storage), zod.
Spielplandaten von [OpenLigaDB](https://www.openligadb.de) (Lizenz ODbL).

## Lokal starten

```bash
pnpm install
cp .env.example .env   # Werte aus dem Supabase-Dashboard eintragen
pnpm dev               # http://localhost:3000
```

| Befehl | Zweck |
|---|---|
| `pnpm lint` / `pnpm typecheck` / `pnpm build` | Prüfungen (Lint und Typecheck laufen auch in der CI) |
| `pnpm exec supabase migration new <name>` | Neue Migration in `supabase/migrations/` |
| `pnpm exec supabase db push --remote` | Migrationen auf das verlinkte Projekt anwenden |
| `pnpm exec supabase gen types typescript --linked > app/types/database.types.ts` | DB-Typen neu erzeugen |
| `pnpm exec supabase db query --remote --yes -f supabase/checks/<datei>.sql` | Logiktests der Datenbank (laufen in einer Transaktion mit Rollback) |

## Deployment auf Vercel

1. **GitHub:** Repository anlegen und den Stand pushen.
2. **Vercel:** Projekt aus dem Repository importieren (Nuxt wird automatisch erkannt) und unter
   *Settings → Environment Variables* eintragen:

   | Variable | Wert |
   |---|---|
   | `NUXT_PUBLIC_SUPABASE_URL` | Project URL aus Supabase |
   | `NUXT_PUBLIC_SUPABASE_KEY` | Publishable Key aus Supabase |
   | `NUXT_SUPABASE_SECRET_KEY` | Secret Key aus Supabase (nur serverseitig) |
   | `NUXT_CRON_SECRET` | Zufälliger Wert, z. B. `openssl rand -hex 32` |
   | `CRON_SECRET` | Derselbe Wert wie `NUXT_CRON_SECRET` (Vercel sendet ihn beim Cron-Aufruf mit) |
   | `NUXT_PUBLIC_SITE_URL` | Produktions-URL, z. B. `https://auswaertsfahrt.example` (für Links in Mails/Push) |
   | `NUXT_SMTP_HOST`, `NUXT_SMTP_PORT` | z. B. `smtp.strato.de`, `465` |
   | `NUXT_SMTP_USER`, `NUXT_SMTP_PASS` | Zugang des Postfachs, über das auch Supabase die Login-Codes schickt |
   | `NUXT_SMTP_FROM` | Absender, z. B. `Auswärtsfahrt <login@deine-subdomain.de>` |
   | `NUXT_PUBLIC_VAPID_PUBLIC_KEY`, `NUXT_VAPID_PRIVATE_KEY` | Schlüsselpaar für Web-Push (`pnpm exec web-push generate-vapid-keys`) |
   | `NUXT_VAPID_SUBJECT` | Optional, z. B. `mailto:login@deine-subdomain.de` (sonst Absender bzw. Site-URL) |

3. **Supabase → Authentication → URL Configuration:** *Site URL* auf die Produktions-Domain setzen
   und `https://<domain>/confirm` unter *Redirect URLs* ergänzen.
4. **Supabase → Authentication → Emails:** Eigenes SMTP muss eingerichtet sein, und die Vorlagen
   „Magic Link“ und „Confirm signup“ müssen `{{ .Token }}` enthalten (Login per Code).
   Unter *Sign In / Providers → Email* muss *Email OTP Length* auf 8 und *Minimum password length*
   auf 8 stehen (passend zu `OTP_LENGTH` und `PASSWORD_MIN_LENGTH` in `app/utils/schemas.ts`).
5. **Täglicher Job prüfen:** `vercel.json` startet täglich um 04:00 UTC `/api/cron/daily`. Er gleicht
   Anstoßzeiten mit OpenLigaDB ab (löst „Anstoßzeit steht fest“ aus), löscht Mitgliedsnummern und
   Ticket-PDFs 30 Tage nach dem Spiel und verschickt liegengebliebene Benachrichtigungen. Manuell:

   ```bash
   curl -H "Authorization: Bearer <CRON_SECRET>" https://<domain>/api/cron/daily
   ```

   Die Antwort zeigt, was abgeglichen, bereinigt und verschickt wurde.

## Benachrichtigungen

Datenbank-Trigger schreiben Benachrichtigungen in die Tabelle `notifications` (Postausgang). Die App
ruft nach passenden Aktionen `POST /api/notifications/dispatch` auf, der Server verschickt sie per
E-Mail (SMTP) und Web-Push und markiert sie als gesendet. Fehlgeschlagene Mails werden bis zu fünfmal
erneut versucht. Den Stand siehst du im Supabase-Dashboard in der Tabelle `notifications`
(`status`, `last_error`).
