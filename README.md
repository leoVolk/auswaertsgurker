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

3. **Supabase → Authentication → URL Configuration:** *Site URL* auf die Produktions-Domain setzen
   und `https://<domain>/confirm` unter *Redirect URLs* ergänzen.
4. **Supabase → Authentication → Emails:** Eigenes SMTP muss eingerichtet sein, und die Vorlagen
   „Magic Link“ und „Confirm signup“ müssen `{{ .Token }}` enthalten (Login per Code).
5. **Löschfrist prüfen:** `vercel.json` startet täglich um 04:00 UTC `/api/cron/cleanup`. Er löscht
   Mitgliedsnummern und Ticket-PDFs 30 Tage nach dem Spiel. Manuell auslösen:

   ```bash
   curl -H "Authorization: Bearer <CRON_SECRET>" https://<domain>/api/cron/cleanup
   ```

   Die Antwort zeigt, wie viele Spiele geprüft und bereinigt wurden.
