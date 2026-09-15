/**
 * ExportCsvButton.tsx — the export entry point for list pages and chat
 * conversations: one PIN step-up, then a CSV / Excel / PDF / Word download
 * (lib/csv.ts), gated by the per-module export permission (lib/permissions.ts).
 *
 * THREE WAYS TO FEED IT
 *   - rows: the page already holds the data (every list page).
 *   - loadRows: the data is loaded only AFTER the PIN is accepted, once per
 *     export (a whole chat conversation, lib/chatExport.ts). Cancelling or
 *     failing the PIN loads nothing.
 *   - onExport: the legacy single-CSV callback.
 *
 * Every step reports its own failure. A PIN the server refused says so; a
 * verify-password request that fails outright (a 500, no network, a 403 "no
 * password is set") is shown through describeError; a failed load says the
 * data couldn't be loaded, and why; a download that throws gets the generic
 * line. One catch used to turn all of these into "Incorrect password", which
 * sent operators to retype a password that was never wrong.
 *
 * KEYBOARD (OPOS #26477)
 * The format menu follows the WAI-ARIA menu button pattern: the trigger
 * carries aria-haspopup/aria-expanded/aria-controls; opening focuses the first
 * item; ArrowUp/ArrowDown wrap, Home/End jump, with a roving tabIndex; Escape
 * closes and returns focus to the trigger; Tab and a click outside close it.
 */
import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react'
import { api, canExportData, describeError } from '../lib/api'
import { useAuth } from '../lib/auth'
import { askForText } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import { useExportAllowed } from '../lib/permissions'
import { downloadCsv, downloadExcel, downloadPdf, downloadWord, type CsvColumn } from '../lib/csv'

type Format = 'csv' | 'excel' | 'pdf' | 'word'

/** The menu's formats, in order, with their label keys. */
const FORMATS: { format: Format; labelKey: string }[] = [
  { format: 'csv', labelKey: 'export.csv' },
  { format: 'excel', labelKey: 'export.excel' },
  { format: 'pdf', labelKey: 'export.pdf' },
  { format: 'word', labelKey: 'export.word' },
]

type Props<T> = {
  // --- 24-b multi-format mode: pass the data + module and get CSV/Excel/PDF ---
  rows?: T[]
  /**
   * Loads the rows once the PIN step-up has succeeded, for data the page does
   * not already hold. Called exactly once per export and takes precedence over
   * `rows`. A rejection is reported as a failed load.
   */
  loadRows?: () => Promise<T[]>
  columns?: CsvColumn<T>[]
  filenameBase?: string
  title?: string
  module?: string
  // --- Legacy CSV-only mode: a callback that builds + downloads the CSV ---
  onExport?: () => void
  /** Button text. Defaults to "Export CSV" in legacy mode and "Export" for the menu. */
  label?: string
  className?: string
}

// 24-b — export entry point for every list page. When given rows (or loadRows)
// + columns + filenameBase it renders a menu (CSV / Excel / PDF / Word) gated
// by the per-module export permission. When given only onExport it stays the
// legacy single CSV button (tier-gated) — so pages migrate incrementally
// without regressions. One PIN step-up either way.
export default function ExportCsvButton<T>({
  rows,
  loadRows,
  columns,
  filenameBase,
  title,
  module,
  onExport,
  label,
  className,
}: Props<T>) {
  const { user } = useAuth()
  const { t } = useI18n()
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const itemRefs = useRef<(HTMLButtonElement | null)[]>([])
  // The one menu item that is tabbable and focused (roving tabIndex).
  const [activeIndex, setActiveIndex] = useState(0)
  const menuId = useId()
  const multi = !!((rows || loadRows) && columns && filenameBase)
  const allowed = useExportAllowed(module ?? '', user)

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    return () => document.removeEventListener('mousedown', onDocClick)
  }, [])

  // Keeps DOM focus on the active item while the menu is open, including the
  // first item right after opening.
  useEffect(() => {
    if (open) itemRefs.current[activeIndex]?.focus()
  }, [open, activeIndex])

  if (multi ? !allowed : !canExportData(user)) return null

  async function verifyPin(): Promise<boolean> {
    // askForText keeps window.prompt's two outcomes: null when the operator
    // backs out (silent abort) and '' when they submit an empty box (the
    // "password is required" toast below). Both callers still depend on the
    // difference.
    const pin = await askForText({
      title: t('auth.password'),
      message: t('export.pin_prompt'),
      secret: true,
    })
    if (pin == null) return false
    if (!pin.trim()) {
      toast.error(t('export.pin_required'))
      return false
    }
    const { data } = await api.post('/api/admin/verify-password', { password: pin })
    if (!data?.ok) {
      toast.error(data?.error || t('export.pin_incorrect'))
      return false
    }
    return true
  }

  // ─── Failure reporting, one step at a time ───

  /**
   * The PIN step-up. A refused PIN is reported inside verifyPin; a request
   * that fails outright is reported as what it is.
   *
   * @returns true only when the server accepted the PIN.
   */
  async function stepUp(): Promise<boolean> {
    try {
      return await verifyPin()
    } catch (e) {
      toast.error(describeError(e))
      return false
    }
  }

  /**
   * The rows to write: loadRows' result when given, else `rows`.
   *
   * @returns the rows, or null when loading failed (already reported).
   */
  async function exportRows(): Promise<T[] | null> {
    if (!loadRows) return rows ?? []
    try {
      return await loadRows()
    } catch (e) {
      toast.error(t('export.load_failed', { reason: describeError(e) }))
      return null
    }
  }

  /**
   * Builds the file. A throw here is a client-side fault with nothing the
   * operator can fix, so they get the generic line and the console the detail.
   */
  function build(write: () => void): void {
    try {
      write()
    } catch (e) {
      console.error('ExportCsvButton: building the export file failed', e)
      toast.error(t('error.unknown'))
    }
  }

  /** Hands the rows to the lib/csv writer for the chosen format. */
  function download(format: Format, data: T[]): void {
    const date = new Date().toISOString().slice(0, 10)
    const base = `${filenameBase}-${date}`
    if (format === 'csv') downloadCsv(`${base}.csv`, data, columns!)
    else if (format === 'excel') downloadExcel(`${base}.xls`, data, columns!)
    else if (format === 'word') downloadWord(`${base}.doc`, title ?? filenameBase!, data, columns!)
    else downloadPdf(title ?? filenameBase!, data, columns!)
  }

  async function runLegacy() {
    if (busy) return
    setBusy(true)
    try {
      if (await stepUp()) build(() => onExport?.())
    } finally {
      setBusy(false)
    }
  }

  // ─── Menu keyboard handling ───

  function toggleMenu() {
    setActiveIndex(0)
    setOpen((o) => !o)
  }

  /** Arrow keys wrap, Home/End jump, Escape returns to the trigger, Tab leaves. */
  function onMenuKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    const last = FORMATS.length - 1
    const moves: Record<string, number> = {
      ArrowDown: activeIndex === last ? 0 : activeIndex + 1,
      ArrowUp: activeIndex === 0 ? last : activeIndex - 1,
      Home: 0,
      End: last,
    }
    if (e.key in moves) {
      e.preventDefault()
      setActiveIndex(moves[e.key])
    } else if (e.key === 'Escape') {
      e.preventDefault()
      setOpen(false)
      triggerRef.current?.focus()
    } else if (e.key === 'Tab') {
      // Not prevented: focus moves on as usual, and the menu closes behind it.
      setOpen(false)
    }
  }

  async function run(format: Format) {
    setOpen(false)
    if (busy || !multi) return
    setBusy(true)
    try {
      if (!(await stepUp())) return
      const data = await exportRows()
      if (data) build(() => download(format, data))
    } finally {
      setBusy(false)
    }
  }

  if (!multi) {
    return (
      <button className={className ?? 'secondary'} onClick={runLegacy} disabled={busy}>
        {label ?? t('common.export_csv')}
      </button>
    )
  }

  return (
    <div ref={ref} style={{ position: 'relative', display: 'inline-block' }}>
      <button
        ref={triggerRef}
        className={className ?? 'secondary'}
        onClick={toggleMenu}
        disabled={busy}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={menuId}
      >
        {label ?? t('export.export')} <span aria-hidden="true">▾</span>
      </button>
      {open && (
        // Note #3 — this used to be styled with var(--card, #fff) /
        // var(--text, #1a1a1a) / var(--border, #e2e2e2). None of --card,
        // --text, --border exist in this theme (the real names are
        // --color-surface-2 / --text-h / --color-border), so every fallback
        // fired: a white menu with light-gray (#C5CCDA, meant for DARK
        // backgrounds) text — nearly unreadable. Moved to a real CSS class
        // using the theme's actual tokens, with a proper :hover state
        // (inline styles can't do :hover at all, which is why there wasn't
        // one before).
        <div id={menuId} className="dropdown-menu" role="menu" onKeyDown={onMenuKeyDown}>
          {FORMATS.map(({ format, labelKey }, index) => (
            <button
              key={format}
              ref={(el) => {
                itemRefs.current[index] = el
              }}
              role="menuitem"
              className="dropdown-menu-item"
              tabIndex={index === activeIndex ? 0 : -1}
              onClick={() => run(format)}
            >
              {t(labelKey)}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
