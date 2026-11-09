# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Auswärtsfahrt – Projektbriefing

## Was wir bauen
Web-App (PWA) für Fußball-Fanclubs: Organisatoren planen Auswärtsfahrten (Bus, Zug, Autos),
verteilen Tickets aus dem Fanclub-Kontingent. Mitglieder melden sich per Link an. Nutzung fast nur auf dem Handy, meist über einen Link
aus einer WhatsApp-Gruppe.

## Tech-Stack
- Nuxt 4 (Quellcode in `app/`), TypeScript strict, `<script setup lang="ts">`
- Nuxt UI v4 + Tailwind CSS v4: ausschließlich Nuxt-UI-Komponenten und Tailwind-Klassen,
  keine weiteren UI-Bibliotheken, eigenes CSS nur in `app/assets/css/main.css`
- Supabase über `@nuxtjs/supabase` (useSupabaseClient, useSupabaseUser),
  generierte Typen in `app/types/database.types.ts`
- Validierung mit zod, auch in UForm
- Spielplan: OpenLigaDB (https://api.openligadb.de), kein API-Key nötig

## Doku nachschlagen
- Vor dem Einsatz einer Nuxt-UI-Komponente IMMER den MCP-Server `nuxt-ui` nach API und
  Beispielen fragen. Kein Wissen aus Nuxt UI v2/v3 verwenden.
- Für Fragen zu Nuxt selbst den MCP-Server `nuxt` nutzen.

## Befehle
Paketmanager ist **pnpm** (`packageManager` in `package.json`, `pnpm-lock.yaml`). Kein npm/npx
verwenden, sonst entsteht eine zweite Lockfile.
- `pnpm dev` – Entwicklungsserver (http://localhost:3000)
- `pnpm build` – Produktions-Build, muss nach jeder Etappe fehlerfrei laufen
- `pnpm lint` (`pnpm lint --fix`) – ESLint
- `pnpm typecheck` – Typprüfung (`nuxt typecheck`)
- `pnpm exec supabase migration new <name>` – neue Migration in `supabase/migrations/`
- `pnpm exec supabase db push` – Migrationen anwenden (nur nach Rückfrage bei mir)
- `pnpm exec supabase gen types typescript --linked > app/types/database.types.ts`
  (das Supabase-Projekt ist bereits verlinkt)

Es gibt noch kein Test-Framework. Die CI (`.github/workflows/ci.yml`, Node 24) führt bei jedem
Push `pnpm lint` und `pnpm typecheck` aus; beides muss grün sein.

## Technische Stolperfallen
- **Stand:** Das Repo ist noch das unveränderte Nuxt-UI-Starter-Template. `app/app.vue`
  (Header/Footer, SEO-Meta, `lang: 'en'`), `app/pages/index.vue`, `AppLogo.vue` und
  `TemplateMenu.vue` sind Platzhalter und werden ersetzt. `app/composables/`, `server/`,
  `supabase/migrations/` und `app/types/database.types.ts` existieren noch nicht.
- **Auth-Redirect:** `nuxt.config.ts` hat noch keinen `supabase`-Block, daher gelten die
  Modul-Defaults: `redirect: true` leitet jede Route ohne Session auf `/login` um, Callback ist
  `/confirm`. Öffentliche Seiten (z. B. Einladungslinks aus WhatsApp) müssen unter
  `supabase.redirectOptions.exclude` eingetragen werden.
- **`useSupabaseUser()`** (`@nuxtjs/supabase` v2) liefert die JWT-Claims aus
  `auth.getClaims()`, kein `User`-Objekt: Die User-ID ist `user.value?.sub`, nicht `.id`.
- **Typen:** Das Modul lädt `~/types/database.types.ts` automatisch, sobald die Datei existiert;
  danach sind `useSupabaseClient()` und die Server-Helfer typisiert. Nach jeder Migration
  die Typen neu generieren.
- **Server-Routen:** `serverSupabaseClient(event)` (läuft als eingeloggter User, RLS greift),
  `serverSupabaseUser(event)`, `serverSupabaseServiceRole(event)` (umgeht RLS, nur wenn nötig).
- **Umgebungsvariablen** in `.env`: `NUXT_PUBLIC_SUPABASE_URL`, `NUXT_PUBLIC_SUPABASE_KEY`;
  ein Secret Key nur als `NUXT_SUPABASE_SECRET_KEY` (landet nicht in `runtimeConfig.public`).
- **Lint-Regeln:** `@nuxt/eslint` mit Stylistic (keine Trailing Commas, 1tbs-Klammern) plus
  `eslint-plugin-better-tailwindcss` (Correctness-Regeln als Error). Klassen werden gegen
  `app/assets/css/main.css` geprüft, auch Objektwerte in `:ui`; unbekannte Klassen lassen den
  Lint scheitern.
- **Theme:** Nuxt-UI-Farben (`primary`, `neutral`) in `app/app.config.ts`, eigene Tokens per
  `@theme` in `main.css`.

## Konventionen
- Code, Bezeichner, Tabellen und Spalten auf Englisch; alle Texte der Oberfläche auf Deutsch, Du-Form
- Mobile first: jede Seite zuerst für 375 px Breite bauen
- Datenbankänderungen nur als Migrationsdatei, nie direkt im Supabase-Dashboard
- Jede Tabelle hat Row Level Security mit Policies; RLS niemals deaktivieren
- Geheime Supabase-Schlüssel nur in Server-Routen (`server/`) über runtimeConfig, nie im Client
- Zeiten in der Datenbank als timestamptz, Anzeige in Europe/Berlin
- Datenzugriff in Composables (`app/composables/use*.ts`), Seiten bleiben schlank

## Fachliche Regeln
- Rollen pro Fanclub: `organizer` und `member`. Nur Organisatoren legen Fahrten an,
  vergeben Plätze und Tickets und bestätigen Zahlungen.
- Teilnahme-Status: requested, confirmed, waitlist, cancelled. Ist eine Fahrt voll, landen
  neue Anmeldungen auf der Warteliste; bei einer Absage rückt der Erste nach.
- Anstoßzeiten können fehlen, solange der Spieltag nicht terminiert ist. Dann "Termin offen"
  anzeigen und alle Angemeldeten benachrichtigen, sobald die Zeit feststeht.
- Tickets: Organisatoren öffnen pro Auswärtsspiel eine Ticketabfrage (Kategorien, Preise, Kontingent,
  Fristen). Jedes Ticket ist eine eigene Anfrage mit Inhabername; Status requested, allocated,
  waitlist, rejected, cancelled. Weitergabe nur zum Originalpreis, kein öffentlicher Verkauf.
- Bezahlen nur per PayPal.Me-Link des Fanclubs mit vorausgefülltem Betrag und kopierbarem
  Verwendungszweck; die App wickelt selbst keine Zahlungen ab. payment_status: open, reported,
  confirmed, refunded. Mitglieder setzen nur open -> reported (Funktion report_payment),
  alles andere nur Organisatoren. Gilt für Tickets und Fahrtkosten.
- Hinterlegung pro Ticket: pickup (Ort/Zeit), box_office (Gästekasse) oder digital (Datei in
  privatem Storage-Bucket, abrufbar nur für Inhaber und Organisatoren).
- Ticketanfragen sehen nur die anfragende Person und Organisatoren. Mitgliedsnummern und
  Ticketdateien 30 Tage nach dem Spiel löschen.
- Treffpunkte und Abfahrtszeiten sind nur für Mitglieder des Fanclubs sichtbar, nie öffentlich.
- Daten aus OpenLigaDB mit Quellenangabe anzeigen (Lizenz ODbL).

## Arbeitsweise
- Bei jeder neuen Etappe zuerst einen Plan vorlegen und auf meine Freigabe warten.
- Nach jeder Etappe: `pnpm lint`, `pnpm typecheck` und `pnpm build` prüfen, kurz
  zusammenfassen, was ich manuell testen soll.
- Keine neuen npm-Pakete ohne Rückfrage installieren.
