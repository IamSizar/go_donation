import { useEffect, useRef, useState } from 'react'
import { api, canExportData } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import { useExportAllowed } from '../lib/permissions'
import { downloadCsv, downloadExcel, downloadPdf, downloadWord, type CsvColumn } from '../lib/csv'

type Format = 'csv' | 'excel' | 'pdf' | 'word'

type Props<T> = {
  // --- 24-b multi-format mode: pass the data + module and get CSV/Excel/PDF ---
  rows?: T[]
  columns?: CsvColumn<T>[]
  filenameBase?: string
  title?: string
  module?: string
  // --- Legacy CSV-only mode: a callback that builds + downloads the CSV ---
  onExport?: () => void
  label?: string
  className?: string
}

// 24-b — export entry point for every list page. When given rows+columns+
// filenameBase it renders a menu (CSV / Excel / PDF) gated by the per-module
// export permission. When given only onExport it stays the legacy single CSV
// button (tier-gated) — so pages migrate incrementally without regressions.
// One PIN step-up either way.
export default function ExportCsvButton<T>({
  rows,
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
  const multi = !!(rows && columns && filenameBase)
  const allowed = useExportAllowed(module ?? '', user)

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    return () => document.removeEventListener('mousedown', onDocClick)
  }, [])

  if (multi ? !allowed : !canExportData(user)) return null

  async function verifyPin(): Promise<boolean> {
    const pin = window.prompt(t('export.pin_prompt'))
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

  async function runLegacy() {
    if (busy) return
    setBusy(true)
    try {
      if (await verifyPin()) onExport?.()
    } catch {
      toast.error(t('export.pin_incorrect'))
    } finally {
      setBusy(false)
    }
  }

  async function run(format: Format) {
    setOpen(false)
    if (busy || !multi) return
    setBusy(true)
    try {
      if (!(await verifyPin())) return
      const date = new Date().toISOString().slice(0, 10)
      const base = `${filenameBase}-${date}`
      if (format === 'csv') downloadCsv(`${base}.csv`, rows!, columns!)
      else if (format === 'excel') downloadExcel(`${base}.xls`, rows!, columns!)
      else if (format === 'word') downloadWord(`${base}.doc`, title ?? filenameBase!, rows!, columns!)
      else downloadPdf(title ?? filenameBase!, rows!, columns!)
    } catch {
      toast.error(t('export.pin_incorrect'))
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

  const itemStyle: React.CSSProperties = {
    display: 'block',
    width: '100%',
    textAlign: 'start',
    padding: '8px 14px',
    background: 'transparent',
    border: 'none',
    cursor: 'pointer',
    font: 'inherit',
    color: 'inherit',
  }

  return (
    <div ref={ref} style={{ position: 'relative', display: 'inline-block' }}>
      <button
        className={className ?? 'secondary'}
        onClick={() => setOpen((o) => !o)}
        disabled={busy}
        aria-haspopup="menu"
        aria-expanded={open}
      >
        {t('export.export')} <span aria-hidden="true">▾</span>
      </button>
      {open && (
        <div
          role="menu"
          style={{
            position: 'absolute',
            zIndex: 30,
            marginTop: 4,
            minWidth: 160,
            background: 'var(--card, #fff)',
            color: 'var(--text, #1a1a1a)',
            border: '1px solid var(--border, #e2e2e2)',
            borderRadius: 10,
            boxShadow: '0 10px 30px rgba(0,0,0,.14)',
            overflow: 'hidden',
          }}
        >
          <button role="menuitem" style={itemStyle} onClick={() => run('csv')}>
            {t('export.csv')}
          </button>
          <button role="menuitem" style={itemStyle} onClick={() => run('excel')}>
            {t('export.excel')}
          </button>
          <button role="menuitem" style={itemStyle} onClick={() => run('pdf')}>
            {t('export.pdf')}
          </button>
          <button role="menuitem" style={itemStyle} onClick={() => run('word')}>
            {t('export.word')}
          </button>
        </div>
      )}
    </div>
  )
}
