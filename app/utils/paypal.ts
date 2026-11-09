/** PayPal.Me-Link mit vorausgefülltem Betrag, z. B. https://paypal.me/MeinFanclub/25.50EUR */
export function paypalMeUrl(name: string, amountCents: number) {
  const amount = amountCents % 100 === 0 ? String(amountCents / 100) : (amountCents / 100).toFixed(2)
  return `https://paypal.me/${encodeURIComponent(name)}/${amount}EUR`
}

/** Akzeptiert den Namen oder einen eingefügten Link (paypal.me/Name, paypal.com/paypalme/Name) */
export function extractPaypalMeName(input: string) {
  const value = input.trim()
  const match = /(?:paypal\.me|paypal\.com\/paypalme)\/([^/?#\s]+)/i.exec(value)
  return (match?.[1] ?? value).replace(/^@/, '')
}

/** Verwendungszweck, mit dem Organisatoren eine Zahlung zuordnen können */
export function paymentReference(parts: { what: string, matchday: number, opponentName: string, payerName: string }) {
  return `${parts.what} ${parts.matchday}. Spieltag ${parts.opponentName} – ${parts.payerName}`.slice(0, 120)
}
