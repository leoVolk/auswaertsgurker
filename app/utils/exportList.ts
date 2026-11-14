// Listen als Excel (.xlsx) oder PDF herunterladen. Die Bibliotheken werden erst beim Export
// geladen, damit sie die App nicht für alle größer machen. Exportiert wird, was die Seite schon
// geladen hat; es gelten also dieselben Rechte (RLS) wie in der Ansicht.

type ExportValue = string | number | null | undefined

export interface ExportColumn<T> {
  header: string
  value: (row: T) => ExportValue
  /** Spaltenbreite in Zeichen (nur Excel) */
  width?: number
}

export interface ExportList<T> {
  title: string
  subtitle?: string
  /** Dateiname ohne Endung, siehe exportFileName() */
  fileName: string
  columns: ExportColumn<T>[]
  rows: T[]
}

/** Dateiname ohne Umlaute und Sonderzeichen, z. B. „tickets-12-spieltag-fc-st-pauli“ */
export function exportFileName(...parts: (string | number)[]) {
  return parts.join('-')
    .toLocaleLowerCase('de-DE')
    .replace(/ä/g, 'ae')
    .replace(/ö/g, 'oe')
    .replace(/ü/g, 'ue')
    .replace(/ß/g, 'ss')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
}

const text = (value: ExportValue) => (value === null || value === undefined ? '' : String(value))

export async function downloadListAsExcel<T>(list: ExportList<T>) {
  const { default: writeExcelFile } = await import('write-excel-file/browser')

  const header = list.columns.map(column => ({ value: column.header, fontWeight: 'bold' as const }))
  const body = list.rows.map(row => list.columns.map((column) => {
    const value = column.value(row)
    return value === null || value === undefined || value === '' ? null : { value }
  }))

  await writeExcelFile([header, ...body], {
    // Excel erlaubt höchstens 31 Zeichen und keine Zeichen wie : / ? * [ ]
    sheet: list.title.replace(/[[\]:*?/\\]/g, ' ').slice(0, 31),
    columns: list.columns.map(column => ({ width: column.width ?? 20 })),
    stickyRowsCount: 1
  }).toFile(`${list.fileName}.xlsx`)
}

export async function downloadListAsPdf<T>(list: ExportList<T>) {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import('jspdf'), import('jspdf-autotable')])

  const doc = new jsPDF({
    orientation: list.columns.length > 5 ? 'landscape' : 'portrait',
    unit: 'pt',
    format: 'a4'
  })
  const margin = 40
  const stand = `Stand: ${formatDateTime(new Date().toISOString())}`

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(15)
  doc.text(list.title, margin, margin + 6)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(9)
  doc.setTextColor(110)
  doc.text(list.subtitle ? `${list.subtitle} · ${stand}` : stand, margin, margin + 22)

  autoTable(doc, {
    startY: margin + 36,
    margin: { left: margin, right: margin, bottom: margin },
    head: [list.columns.map(column => column.header)],
    body: list.rows.map(row => list.columns.map(column => text(column.value(row)))),
    styles: { font: 'helvetica', fontSize: 9, cellPadding: 5, textColor: 30, lineColor: 225, lineWidth: 0.5 },
    headStyles: { fillColor: 242, textColor: 30, fontStyle: 'bold' },
    theme: 'grid'
  })

  // Fußzeile mit Seitenzahlen erst am Ende, wenn die Gesamtzahl feststeht
  const pages = doc.getNumberOfPages()
  const pageWidth = doc.internal.pageSize.getWidth()
  const pageHeight = doc.internal.pageSize.getHeight()
  doc.setFontSize(8)
  doc.setTextColor(140)
  for (let page = 1; page <= pages; page++) {
    doc.setPage(page)
    doc.text('Auswärtsgurker', margin, pageHeight - 20)
    doc.text(`Seite ${page} von ${pages}`, pageWidth - margin, pageHeight - 20, { align: 'right' })
  }

  doc.save(`${list.fileName}.pdf`)
}

/** Menüeinträge „Als PDF“ und „Als Excel“ für ein UDropdownMenu */
export function exportMenuItems<T>(list: () => ExportList<T>, onError: (error: unknown) => void) {
  const run = (download: (list: ExportList<T>) => Promise<void>) => async () => {
    try {
      await download(list())
    } catch (error) {
      onError(error)
    }
  }
  return [
    { label: 'Als PDF herunterladen', icon: 'i-lucide-file-text', onSelect: run(downloadListAsPdf) },
    { label: 'Als Excel herunterladen', icon: 'i-lucide-file-spreadsheet', onSelect: run(downloadListAsExcel) }
  ]
}
