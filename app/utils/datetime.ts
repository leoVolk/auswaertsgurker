// Alle Zeiten werden als UTC gespeichert und in Europe/Berlin angezeigt und eingegeben.
const TIME_ZONE = 'Europe/Berlin'

const dateTimeFormat = new Intl.DateTimeFormat('de-DE', {
  timeZone: TIME_ZONE,
  weekday: 'short',
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
  minute: '2-digit'
})

const dateFormat = new Intl.DateTimeFormat('de-DE', {
  timeZone: TIME_ZONE,
  day: '2-digit',
  month: '2-digit'
})

const partsFormat = new Intl.DateTimeFormat('en-US', {
  timeZone: TIME_ZONE,
  hourCycle: 'h23',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit'
})

const priceFormat = new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR' })

/** z. B. „Sa., 21.11., 15:30 Uhr“ */
export function formatDateTime(iso: string) {
  return `${dateTimeFormat.format(new Date(iso))} Uhr`
}

/** z. B. „21.11.“ */
export function formatDayMonth(iso: string) {
  return `${dateFormat.format(new Date(iso))}.`
}

export function formatPrice(cents: number) {
  return priceFormat.format(cents / 100)
}

function berlinParts(date: Date) {
  const parts = Object.fromEntries(
    partsFormat.formatToParts(date).map(part => [part.type, part.value])
  )
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute)
  }
}

/** Abstand der Berliner Ortszeit zu UTC in Millisekunden zum Zeitpunkt `timestamp` */
function berlinOffset(timestamp: number) {
  const p = berlinParts(new Date(timestamp))
  const wallClock = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute)
  return wallClock - Math.floor(timestamp / 60_000) * 60_000
}

const pad = (value: number) => String(value).padStart(2, '0')

/** ISO-Zeitpunkt → Wert für `<input type="datetime-local">` in Berliner Zeit */
export function toBerlinInput(iso: string | null | undefined) {
  if (!iso) return ''
  const p = berlinParts(new Date(iso))
  return `${p.year}-${pad(p.month)}-${pad(p.day)}T${pad(p.hour)}:${pad(p.minute)}`
}

/** Wert aus `<input type="datetime-local">` (Berliner Zeit) → ISO-Zeitpunkt in UTC */
export function fromBerlinInput(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value)
  if (!match) return null

  const [year, month, day, hour, minute] = match.slice(1, 6).map(Number) as [number, number, number, number, number]
  const wallClock = Date.UTC(year, month - 1, day, hour, minute)
  // Zweimal rechnen, damit die Umstellung auf Sommer-/Winterzeit stimmt
  const guess = wallClock - berlinOffset(wallClock)
  return new Date(wallClock - berlinOffset(guess)).toISOString()
}
