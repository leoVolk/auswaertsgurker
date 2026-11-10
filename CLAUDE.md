# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Auswärtsgurker – Projektbriefing

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
- `pnpm exec supabase db push --remote` – Migrationen anwenden (nur nach Rückfrage bei mir).
  Supabase CLI v3 zielt ohne `--remote` auf eine lokale Docker-Datenbank.
- `pnpm exec supabase gen types typescript --linked > app/types/database.types.ts`
  (das Supabase-Projekt ist bereits verlinkt; die Datei ist vom Lint ausgenommen)

Es gibt noch kein Test-Framework. Die CI (`.github/workflows/ci.yml`, Node 24) führt bei jedem
Push `pnpm lint` und `pnpm typecheck` aus; beides muss grün sein.

DB-Logik (RPCs, Trigger, RLS) wird mit SQL-Skripten in `supabase/checks/` geprüft:
`pnpm exec supabase db query --remote --yes -f supabase/checks/<datei>.sql`. Die Skripte laufen in
`begin … rollback`, legen Testnutzer direkt in `auth.users` an und wechseln per
`set local role authenticated` + `set_config('request.jwt.claims', '{"sub": …}', true)` die Identität.
Neue Logik nach demselben Muster testen. `pnpm exec supabase db advisors --remote` prüft das
Schema auf Sicherheitsprobleme.

## Architektur
- **Datenmodell:** `profiles` (1:1 zu `auth.users`, per Trigger angelegt), `clubs` (inkl.
  Verein aus OpenLigaDB), `club_members` (Rolle als Enum `club_role`), `club_invites` (ein aktiver
  Link pro Club), `away_games` (Auswärtsspiel pro Club, Anker für Fahrten und Ticketabfragen,
  angelegt per RPC `ensure_away_game`), `trips`, `trip_registrations` (eine Zeile pro Person und
  Fahrt; Reihenfolge der Warteliste über `status_changed_at`). Tabellen mit `club_id`, die auf eine andere
  Club-Tabelle zeigen, nutzen einen zusammengesetzten Fremdschlüssel `(x_id, club_id)`, damit
  nichts clubübergreifend verknüpft werden kann.
- **OpenLigaDB:** Nur über die Server-Routen `server/api/openligadb/*` (gecacht in
  `server/utils/openligadb.ts`), nie direkt aus dem Client. Nicht terminierte Spieltage erkennt man
  daran, dass alle Spiele denselben Platzhalter-Anstoß haben (Ausnahme: letzter Spieltag) →
  `kickoffAt: null` plus `provisionalAt`. Angezeigt wird die Live-Zeit aus OpenLigaDB, in
  `away_games.kickoff_at` steht der Stand beim Planen. Keine Vereinswappen laden (externe Hosts,
  IP-Weitergabe).
- **`shared/`:** Typen und Helfer für App und Server (`LeagueShortcut`, `currentSeason()`,
  `AwayMatch`); Import per `#shared/...`.
- **Zeiten:** Ein- und Ausgabe in Europe/Berlin über `app/utils/datetime.ts`
  (`formatDateTime`, `toBerlinInput`/`fromBerlinInput` für `<UInput type="datetime-local">`).
- **RLS-Muster:** Policies nutzen die `security definer`-Funktionen `private.is_club_member(club_id)`
  und `private.is_club_organizer(club_id)`, damit es keine Rekursion auf `club_members` gibt.
  Schreibvorgänge über mehrere Tabellen oder ohne direkte Insert-Policy laufen über RPCs
  (`create_club`, `join_club`, `regenerate_invite`; `get_invite` ist auch ohne Login aufrufbar).
- **Schemas:** `public` ist das API-Schema; jede Funktion dort ist per RPC erreichbar. Nur bewusst
  aufrufbare RPCs (prüfen Rechte selbst) gehören nach `public`. Rechte-Prüfungen für Policies und
  interne Helfer liegen in `private` (nicht exponiert; `authenticated` hat nur USAGE) und werden
  voll qualifiziert aufgerufen (`private.is_club_organizer(…)`). Trigger-Funktionen bleiben in
  `public` (über die API nicht aufrufbar). Der Security-Advisor meldet die RPCs in `public`
  absichtlich weiterhin.
- **Anmeldungen:** Statuswechsel nur über RPCs (`register_for_trip`, `cancel_trip_registration`,
  `confirm_trip_registration`, `confirm_all_trip_registrations`), die die Fahrt per `for update`
  sperren. Nachrücken zentral in `promote_trip_waitlist` (auch per Trigger bei mehr Plätzen und beim
  Entfernen eines Mitglieds). `requested` belegt bereits einen Platz. Mitglieder lesen nur die
  eigene Anmeldung; Belegungszahlen kommen aus `get_trip_stats`, weil in diesen Zeilen künftig
  auch der Zahlungsstatus steht.
- **Tickets:** `ticket_rounds` (eine pro `away_game`) → `ticket_categories` (Preis, Kontingent,
  `null` = noch offen) → `ticket_requests` (ein Ticket pro Zeile, Inhaber + optionale
  Mitgliedsnummer). Zuteilung durch Organisatoren per `set_ticket_request_status` (prüft das
  Kontingent unter Sperre) bzw. `auto_allocate_tickets` (nach Anfragezeitpunkt, Rest →
  Warteliste); kein automatisches Nachrücken. Mitglieder schreiben nur über `request_ticket`,
  `update_ticket_request_holder` und `cancel_ticket_request` (nur solange nicht zugeteilt).
  Kategorien mit Anfragen sind per Fremdschlüssel (NO ACTION) gegen Löschen geschützt.
- **Ticket-Hinterlegung:** `ticket_requests.delivery_method` (`pickup` mit Ort/Zeit, `box_office`,
  `digital`). PDFs liegen im privaten Bucket `ticket-files` unter `<club_id>/<request_id>.pdf`;
  Storage-Policies über `can_read_ticket_file` (anfragende Person nur bei zugeteiltem und
  angehängtem Ticket, Organisatoren immer), `can_upload_ticket_file`, `can_delete_ticket_file`.
  Ablauf: Upload per Storage-API → `attach_ticket_file`; Lösen per `detach_ticket_file` bzw.
  `set_ticket_delivery`, die zurückgegebenen Pfade löscht der Client aus dem Storage.
  Downloads nur über kurzlebige signierte URLs. Storage-Dateien nie per SQL löschen.
- **Zahlungen:** `payment_status` an `trip_registrations` und `ticket_requests`, PayPal.Me-Name in
  `clubs.paypal_me`. Mitglieder melden per `report_payment(p_trip_registration_ids,
  p_ticket_request_ids)` (nur eigene, bezahlbare Posten: Fahrt mit Platz, zugeteiltes Ticket);
  Organisatoren per `set_payment_status` (bestätigen, auch bar; offen; erstatten nur bestätigte).
  Der Betrag wird beim Melden/Bestätigen in `payment_amount_cents` festgehalten. Mehrere Tickets
  einer Person werden gemeinsam bezahlt (ein Link, ein Verwendungszweck), der Status bleibt pro
  Ticket. Link-Format: `paypal.me/<Name>/<Betrag>EUR` mit Punkt als Dezimaltrenner
  (`app/utils/paypal.ts`). `ticket_rounds.download_requires_payment` sperrt das PDF bis zur
  Bestätigung (Storage-Policy).
- **Benachrichtigungen:** DB-Trigger schreiben deutschsprachige Einträge (Titel, Text, App-Pfad) in
  `notifications` (Postausgang; Mitglieder lesen nur eigene). Neue Ereignisse = neuer Trigger, der
  `enqueue_notifications` aufruft, plus Wert im Enum `notification_kind`. Versand in
  `server/utils/notify.ts`: `claim_notifications` (Sperre, max. 5 Versuche) → gruppieren nach
  Person/Art/Ziel → E-Mail via `nodemailer` (`runtimeConfig.smtp`, nur wenn
  `profiles.email_notifications`) und Push via `web-push` (`push_subscriptions`, abgelaufene Abos
  werden gelöscht) → `complete_notifications`. Angestoßen von der App über
  `useNotificationDispatch()` (entprellt, nach Aktionen in den Action-Composables) und vom täglichen
  Cron. `web-push` 4 ist ESM ohne Default-Export: nur benannte Importe.
- **PWA:** `public/manifest.webmanifest`, `public/sw.js` (nur Push und Klick, kein Offline-Cache),
  Icons in `public/icons/` (Platzhalter aus `icon.svg`), Registrierung in `app/plugins/pwa.client.ts`.
  Profil mit E-Mail-Schalter, Push-Opt-in und Installationshinweis unter `/profile`.
- **Täglicher Job:** `server/api/cron/daily.get.ts` (Vercel Cron, `vercel.json`, geschützt mit
  `runtimeConfig.cronSecret` = `NUXT_CRON_SECRET`, Vercel sendet `CRON_SECRET` als Bearer-Token):
  Anstoßzeiten abgleichen (`syncKickoffTimes`), Löschfrist, liegengebliebene Benachrichtigungen.
- **Löschfrist:**
  `server/utils/retention.ts` prüft per OpenLigaDB, welche Spiele beendet und älter als
  `TICKET_DATA_RETENTION_DAYS` sind, löscht deren PDFs über die Storage-API (Service Role) und ruft
  dann `purge_away_game_ticket_data` auf (nur `service_role`; markiert
  `away_games.personal_data_purged_at`). Reihenfolge Dateien → DB, damit ein abgebrochener Lauf
  am nächsten Tag einfach wiederholt wird.
- **Deployment:** Vercel, Schritte und Umgebungsvariablen in `README.md`, Vorlage in `.env.example`.
- **Node-Typen:** `@types/node` ist nicht installiert; in `nuxt.config.ts` und Server-Code kein
  `process`, `Buffer` oder `node:*` verwenden (Konfiguration über `runtimeConfig` + `NUXT_*`-Variablen).
- **Fanclub löschen/verlassen:** Löschen nur für Organisatoren (Policy auf `clubs`), endgültig per
  Kaskade; Ticket-PDFs löscht der Client vorher über die Storage-API (`useClubMembershipEnd`).
  Vorschau mit Warnung bei bestätigten Zahlungen für kommende Spiele über `club_deletion_summary`.
  Verlassen = eigene Zeile in `club_members` löschen; der Trigger storniert Fahrt-Anmeldungen
  (Warteliste rückt nach) und offene Ticketanfragen, zugeteilte Tickets bleiben. Trigger auf
  `club_members` müssen beim Löschen des ganzen Fanclubs (Kaskade) aussteigen:
  `if not exists (select 1 from public.clubs where id = old.club_id)`.
- **Spaltenrechte:** Für `authenticated` ist UPDATE auf Tabellenebene entzogen und nur für
  fachlich änderbare Spalten gewährt (`grant update (col) ...`). Neue änderbare Spalten brauchen
  in der Migration ein eigenes `grant update`, sonst schlägt das Update mit 42501 fehl.
- **Fehlermeldungen:** `raise exception` in DB-Funktionen auf Deutsch formulieren; `errorMessage()`
  (`app/utils/errors.ts`) gibt Meldungen mit Code P0001 direkt an die Oberfläche weiter. Im
  Client erzeugte Meldungen als `throw new UserError('…')`.
- **Composables:** Lesende Composables sind `async` und kapseln `await useAsyncData(...)`; Seiten
  rufen sie mit `await` auf. Pro Fanclub-Seite liefert `useClub(id)` den Club samt eigener Rolle
  (`null` = kein Mitglied).
- **Login:** E-Mail-Code (`signInWithOtp` + `verifyOtp`) statt Magic Link, weil Links aus der
  Mail im WhatsApp-In-App-Browser am PKCE-Flow scheitern. Der Code hat 8 Ziffern (`OTP_LENGTH` in
  `app/utils/schemas.ts`, muss zu „Email OTP Length“ in Supabase passen) und wird per `UPinInput`
  eingegeben; bei vollständiger Eingabe schickt das Formular automatisch ab. `/confirm` ist nur ein Fallback, falls
  die E-Mail-Vorlage noch einen Link enthält. `onboarding.global.ts` erzwingt einen Anzeigenamen.
- **Passwort (optional):** Registrierung immer per Code (bestätigt die Adresse). Danach kann man im
  Profil ein Passwort festlegen (`useSetPassword`: `updateUser` + Markierung `has_password` in
  `user_metadata`, danach `refreshSession`, weil `useSupabaseUser()` die Token-Claims liest).
  Login-Seite mit Tabs „Code per E-Mail“/„Passwort“; die zuletzt erfolgreiche Methode merkt sich
  der Cookie `login-method`. Kein Reset-Link per Mail (PKCE-Problem wie beim Magic Link):
  vergessenes Passwort = per Code anmelden und im Profil neu setzen. `PASSWORD_MIN_LENGTH` muss
  zu „Minimum password length“ in Supabase passen.
- **Sitzungsdauer:** `supabase.cookieOptions.maxAge` in `nuxt.config.ts` ist auf ein Jahr gesetzt
  (Modul-Standard wären 8 Stunden, danach müsste man sich neu anmelden).
- **Mailversand:** Die Auth-Mails laufen über eigenes SMTP (Strato, Subdomain), eingetragen im
  Supabase-Dashboard. Ohne eigenes SMTP sind im Free-Plan die Vorlagen gesperrt, und der
  eingebaute Versand stellt nur an Team-Mitglieder zu. Die Vorlagen „Magic Link“ und „Confirm
  signup“ müssen `{{ .Token }}` enthalten.

## Technische Stolperfallen
- **Auth-Redirect:** `redirect: true` (Modul-Default) leitet jede Route ohne Session auf
  `/login` um. Öffentliche Seiten in `nuxt.config.ts` unter `supabase.redirectOptions.exclude`
  eintragen (aktuell `/join/*`). `saveRedirectToCookie` merkt sich das Ziel; auf
  ausgenommenen Seiten den Cookie vor dem Login selbst setzen (`useSupabaseCookieRedirect`).
- **`useSupabaseUser()`** (`@nuxtjs/supabase` v2) liefert die JWT-Claims aus
  `auth.getClaims()`, kein `User`-Objekt: Die User-ID ist `.sub`, nicht `.id`. Im Code
  `useCurrentUserId()` verwenden. Nach einem Login setzt das Modul den User erst asynchron,
  deshalb vor der Weiterleitung `useSyncSupabaseUser()` aufrufen. `useSupabaseSession()` hat
  keine `user`-Eigenschaft.
- **Imports:** `@supabase/supabase-js` ist keine direkte Abhängigkeit und mit pnpm nicht
  importierbar, auch nicht nur für Typen.
- **RPC-Parameter mit `null`:** Die generierten Typen kennen bei Funktionsargumenten kein `null`.
  Parameter trotzdem immer mitschicken (`value as string`), nie weglassen, sonst findet PostgREST
  die Funktion nicht.
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
