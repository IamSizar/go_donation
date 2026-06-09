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

export function downloadCsv<T>(filename: string, rows: T[], columns: CsvColumn<T>[]): void {
  const header = columns.map((c) => escapeCell(c.header)).join(',')
  const body = rows.map((r) => columns.map((c) => escapeCell(c.get(r))).join(',')).join('\n')
  // BOM ensures Excel detects UTF-8 (Arabic/Kurdish columns otherwise garble)
  const csv = '﻿' + header + '\n' + body
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
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
