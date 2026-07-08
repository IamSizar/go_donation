// CSV export helper used by every list page in Phase 12.
//
// `downloadCsv` takes an array of plain rows, a list of column specs
// (header label + getter that returns a primitive for that row), and a
// filename. It builds a UTF-8 CSV with a BOM (so Excel opens Arabic/Sorani
// correctly), escapes per RFC 4180, and triggers a browser download.
//
// Why not server-side: the visible rows are already in the SPA. Re-fetching
// from a /export endpoint would duplicate the SELECT logic. Client-side keeps
// the export aligned with whatever filter/page the admin is currently looking
// at — what you see is what you get.

export type CsvColumn<T> = {
  header: string
  get: (row: T) => unknown
}

function escapeCell(v: unknown): string {
  if (v === null || v === undefined) return ''
  let s: string
  if (v instanceof Date) s = v.toISOString()
  else if (typeof v === 'object') s = JSON.stringify(v)
  else s = String(v)
  // Per RFC 4180: wrap in quotes if contains comma, quote, newline, or CR.
  if (/[",\r\n]/.test(s)) {
    s = '"' + s.replace(/"/g, '""') + '"'
  }
  return s
}

// Plain text of a cell value (no CSV quoting) — shared by Excel + PDF.
function cellText(v: unknown): string {
  if (v === null || v === undefined) return ''
  if (v instanceof Date) return v.toISOString()
  if (typeof v === 'object') return JSON.stringify(v)
  return String(v)
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function triggerDownload(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  setTimeout(() => {
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }, 0)
}

function isRtl(): boolean {
  return typeof document !== 'undefined' && document.documentElement.dir === 'rtl'
}

export function downloadCsv<T>(filename: string, rows: T[], columns: CsvColumn<T>[]): void {
  const header = columns.map((c) => escapeCell(c.header)).join(',')
  const body = rows.map((r) => columns.map((c) => escapeCell(c.get(r))).join(',')).join('\n')
  // BOM ensures Excel detects UTF-8 (Arabic/Kurdish columns otherwise garble)
  const csv = '﻿' + header + '\n' + body
  triggerDownload(new Blob([csv], { type: 'text/csv;charset=utf-8' }), filename)
}

// 24-b — Excel export, dependency-free. Builds a UTF-8 HTML table saved with the
// Excel MIME type; Excel, Numbers and Google Sheets all open it natively as a
// spreadsheet. The BOM + <meta charset> keep Arabic/Kurdish text intact.
export function downloadExcel<T>(filename: string, rows: T[], columns: CsvColumn<T>[]): void {
  const rtl = isRtl()
  const align = rtl ? 'right' : 'left'
  const thead =
    '<tr>' +
    columns
      .map(
        (c) =>
          `<th style="background:#0E5B54;color:#fff;border:1px solid #999;padding:4px 8px;text-align:${align}">${escapeHtml(c.header)}</th>`,
      )
      .join('') +
    '</tr>'
  const tbody = rows
    .map(
      (r) =>
        '<tr>' +
        columns
          .map(
            (c) =>
              `<td style="border:1px solid #ccc;padding:3px 8px;text-align:${align}">${escapeHtml(cellText(c.get(r)))}</td>`,
          )
          .join('') +
        '</tr>',
    )
    .join('')
  const html =
    '﻿<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">' +
    `<head><meta charset="utf-8"></head><body><table dir="${rtl ? 'rtl' : 'ltr'}" border="1">${thead}${tbody}</table></body></html>`
  triggerDownload(new Blob([html], { type: 'application/vnd.ms-excel;charset=utf-8' }), filename)
}

// #51 — Word export, dependency-free. Builds a UTF-8 HTML document saved with
// the Word MIME type (.doc); Microsoft Word, Pages and Google Docs all open it
// natively as a document. Includes a title + timestamp + row count. RTL-aware.
export function downloadWord<T>(
  filename: string,
  title: string,
  rows: T[],
  columns: CsvColumn<T>[],
): void {
  const rtl = isRtl()
  const align = rtl ? 'right' : 'left'
  const thead =
    '<tr>' +
    columns
      .map(
        (c) =>
          `<th style="background:#0E5B54;color:#fff;border:1px solid #999;padding:4px 8px;text-align:${align}">${escapeHtml(c.header)}</th>`,
      )
      .join('') +
    '</tr>'
  const tbody = rows
    .map(
      (r) =>
        '<tr>' +
        columns
          .map(
            (c) =>
              `<td style="border:1px solid #ccc;padding:3px 8px;text-align:${align}">${escapeHtml(cellText(c.get(r)))}</td>`,
          )
          .join('') +
        '</tr>',
    )
    .join('')
  const stamp = new Date().toLocaleString()
  const html =
    '﻿<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word">' +
    `<head><meta charset="utf-8"><title>${escapeHtml(title)}</title></head>` +
    `<body dir="${rtl ? 'rtl' : 'ltr'}">` +
    `<h2 style="font-family:Arial,sans-serif;margin:0 0 2px">${escapeHtml(title)}</h2>` +
    `<p style="font-family:Arial,sans-serif;color:#666;font-size:12px;margin:0 0 12px">${escapeHtml(stamp)} · ${rows.length} rows</p>` +
    `<table border="1" style="border-collapse:collapse;font-family:Arial,sans-serif;font-size:12px">${thead}${tbody}</table>` +
    '</body></html>'
  triggerDownload(new Blob([html], { type: 'application/msword;charset=utf-8' }), filename)
}

// 24-b — PDF export, dependency-free. Opens a print window with a styled table
// and triggers the browser's print dialog, where the admin chooses "Save as
// PDF". RTL-aware; includes a title + timestamp + row count.
export function downloadPdf<T>(title: string, rows: T[], columns: CsvColumn<T>[]): void {
  const rtl = isRtl()
  const align = rtl ? 'right' : 'left'
  const thead =
    '<tr>' + columns.map((c) => `<th>${escapeHtml(c.header)}</th>`).join('') + '</tr>'
  const tbody = rows
    .map(
      (r) =>
        '<tr>' + columns.map((c) => `<td>${escapeHtml(cellText(c.get(r)))}</td>`).join('') + '</tr>',
    )
    .join('')
  const stamp = new Date().toLocaleString()
  const doc = `<!doctype html><html dir="${rtl ? 'rtl' : 'ltr'}"><head><meta charset="utf-8"><title>${escapeHtml(
    title,
  )}</title>
<style>
  * { font-family: -apple-system, "Segoe UI", Tahoma, Arial, sans-serif; }
  body { margin: 24px; color: #1a1a1a; }
  h1 { font-size: 18px; margin: 0 0 2px; }
  .meta { color: #666; font-size: 12px; margin: 0 0 16px; }
  table { border-collapse: collapse; width: 100%; font-size: 12px; }
  th, td { border: 1px solid #ccc; padding: 5px 8px; text-align: ${align}; vertical-align: top; }
  thead th { background: #0E5B54; color: #fff; }
  tbody tr:nth-child(even) { background: #f5f7f7; }
  @media print { thead { display: table-header-group; } }
</style></head>
<body>
  <h1>${escapeHtml(title)}</h1>
  <p class="meta">${escapeHtml(stamp)} · ${rows.length} rows</p>
  <table>${thead}${tbody}</table>
</body></html>`
  const win = window.open('', '_blank')
  if (!win) return
  win.document.open()
  win.document.write(doc)
  win.document.close()
  const go = () => {
    win.focus()
    win.print()
  }
  if (win.document.readyState === 'complete') setTimeout(go, 300)
  else win.onload = () => setTimeout(go, 300)
}
