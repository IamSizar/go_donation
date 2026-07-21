// EditModal — generic edit form host used by every list page in Phase 10.
//
// Caller supplies:
//   • title             – heading text ("Edit partner #5")
//   • initial           – current row values keyed by column name
//   • fields            – ordered list of FieldSpec (label, column, type, etc.)
//   • onSave(patch)     – called with ONLY the columns whose values changed,
//                         returns Promise. On success the modal closes; on
//                         failure the error is shown and the modal stays open.
//
// What the modal handles for the caller:
//   • Local form state + change tracking
//   • Submit button enabled only when at least one field changed
//   • Inline error if onSave rejects
//   • Esc-to-close, click-outside-to-close, "Cancel" button
//   • Disables fields while save is in flight
//
// Field types: text, textarea, number, select. Anything more exotic the page
// can render with a custom `render` field — but for Phase 10 these four cover
// every column we care about.

import { useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { describeError } from '../lib/api'
import { useI18n, useStatusLabel } from '../lib/i18n'
import FileInput from './FileInput'
import GalleryInput from './GalleryInput'

export type FieldType = 'text' | 'textarea' | 'number' | 'date' | 'select' | 'file' | 'gallery' | 'multiselect' | 'password'

export type FieldSpec = {
  key: string                  // JSON key sent to backend + initial values key
  label: string                // shown above the input (English fallback)
  labelKey?: string            // i18n key; when set, resolved via t() instead of `label`
  type: FieldType
  options?: string[]           // for type='select'
  optionLabels?: Record<string, string> // for type='select': value → display label (else statusLabel(value))
  placeholder?: string
  rows?: number                // for textarea
  required?: boolean           // disallow empty on save
  dir?: 'ltr' | 'rtl' | 'auto' // text direction hint (rtl for Arabic / Kurdish)
  // For type='file': optional accept string (defaults to 'image/*' inside FileInput)
  accept?: string
  // For type='file': hide the preview thumbnail (e.g. for PDFs)
  hidePreview?: boolean
  // Force a field to take the full grid width regardless of column layout
  full?: boolean
}

type Props = {
  open: boolean
  title: string
  initial: Record<string, unknown>
  fields: FieldSpec[]
  onSave: (patch: Record<string, unknown>) => Promise<unknown>
  onClose: () => void
  // 'edit' (default) sends only changed fields. 'create' sends every field the
  // admin filled in — used by the "New" buttons in Phase 11.
  mode?: 'edit' | 'create'
  // Override the primary button text. Defaults to "Save changes" / "Create".
  saveLabel?: string
}

function toInputValue(v: unknown): string {
  if (v === null || v === undefined) return ''
  return typeof v === 'string' ? v : String(v)
}

export default function EditModal({ open, title, initial, fields, onSave, onClose, mode = 'edit', saveLabel }: Props) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const initialStrings = useMemo(() => {
    const m: Record<string, string> = {}
    for (const f of fields) {
      if (f.type === 'gallery' || f.type === 'multiselect') {
        // Serialize the array column to a JSON string so it fits the string map.
        const v = initial[f.key]
        m[f.key] = JSON.stringify(Array.isArray(v) ? v : [])
      } else {
        m[f.key] = toInputValue(initial[f.key])
      }
    }
    return m
  }, [initial, fields])

  const [values, setValues] = useState<Record<string, string>>(initialStrings)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const firstRef = useRef<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | null>(null)

  // Note #16 — reset state only on the false→true transition (the modal
  // actually opening), not on every render where `initialStrings` happens to
  // be a new object. Callers commonly pass an inline `initial={{}}` /
  // `initial={creating ? {} : row}` literal, which is a brand-new reference
  // every render of the PARENT — and several parent pages poll every 5-10s
  // for live updates. With the old `[open, initialStrings]` dependency, that
  // poll-triggered re-render alone re-ran this effect and wiped whatever the
  // admin had typed, even though the modal never closed. Tracking the
  // previous `open` value via a ref keeps the "reset on open" behavior while
  // ignoring `initialStrings` identity churn that happens while already open.
  const wasOpenRef = useRef(false)
  useEffect(() => {
    const wasOpen = wasOpenRef.current
    wasOpenRef.current = open
    if (!open || wasOpen) return
    setValues(initialStrings)
    setBusy(false)
    setErr(null)
    setTimeout(() => firstRef.current?.focus(), 50)
  }, [open, initialStrings])

  // Esc-to-close.
  useEffect(() => {
    if (!open) return
    function handle(e: KeyboardEvent) {
      if (e.key === 'Escape' && !busy) onClose()
    }
    window.addEventListener('keydown', handle)
    return () => window.removeEventListener('keydown', handle)
  }, [open, busy, onClose])

  // We return an AnimatePresence wrapper always so exit animations get a
  // chance to play when `open` flips false. The empty branch returns null
  // when not open, but it's inside <AnimatePresence> so React doesn't unmount
  // the tree until the exit transition finishes.

  // In edit mode: diff against initialStrings, send only changed fields.
  // In create mode: send every field the admin filled in (skip empty optional
  // fields so the backend default kicks in; send empty for changed-to-empty in
  // edit mode so the column gets set to NULL).
  function buildPatch(): Record<string, unknown> {
    const patch: Record<string, unknown> = {}
    for (const f of fields) {
      const next = values[f.key] ?? ''
      const before = initialStrings[f.key] ?? ''
      if (mode === 'edit') {
        if (next === before) continue
      } else {
        // create mode — skip blanks for non-required fields entirely
        if (next === '' && !f.required) continue
      }
      if (f.type === 'gallery' || f.type === 'multiselect') {
        let arr: string[] = []
        try {
          const parsed = JSON.parse(next || '[]')
          arr = Array.isArray(parsed) ? parsed.map((x) => String(x)).filter((s) => s.trim() !== '') : []
        } catch {
          arr = []
        }
        // In create mode, an empty array adds nothing — let the DB default.
        if (mode === 'create' && arr.length === 0) continue
        patch[f.key] = arr
        continue
      }
      if (f.type === 'number') {
        if (next === '') {
          patch[f.key] = null
        } else {
          const n = Number(next)
          patch[f.key] = isFinite(n) ? n : next
        }
      } else {
        patch[f.key] = next
      }
    }
    return patch
  }

  async function handleSave() {
    setErr(null)
    // Required-field check (only when the field changed to empty).
    for (const f of fields) {
      if (f.required) {
        const v = (values[f.key] ?? '').trim()
        if (v === '') {
          const lbl = f.labelKey ? t(f.labelKey) : f.label
          setErr(`${lbl} ${t('common.required')}.`)
          return
        }
      }
    }
    const patch = buildPatch()
    if (Object.keys(patch).length === 0) {
      onClose()
      return
    }
    setBusy(true)
    try {
      await onSave(patch)
      onClose()
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="modal-overlay"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.18 }}
          onClick={(e) => {
            if (e.target === e.currentTarget && !busy) onClose()
          }}
        >
          <motion.div
            className="modal-card"
            role="dialog"
            aria-modal="true"
            aria-label={title}
            initial={{ opacity: 0, scale: 0.94, y: 12 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96, y: 8 }}
            transition={{ type: 'spring', stiffness: 320, damping: 28 }}
          >
        <div className="modal-head">
          <h2>{title}</h2>
          <button className="icon" onClick={onClose} disabled={busy} aria-label={t('common.close')}>×</button>
        </div>
        <div className="modal-body">
          {err && <div className="error-box" style={{ marginBottom: 12 }}>{err}</div>}
          <div className="form-grid">
            {fields.map((f, i) => {
              const v = values[f.key] ?? ''
              const setV = (next: string) => setValues((m) => ({ ...m, [f.key]: next }))
              const label = f.labelKey ? t(f.labelKey) : f.label
              const dir = f.dir ?? 'auto'
              const ref = i === 0 ? firstRef : undefined

              if (f.type === 'file') {
                return (
                  <div key={f.key} className={`form-row${f.full ? ' full' : ''}`}>
                    <span className="form-label">{label}{f.required && <span className="req">*</span>}</span>
                    <FileInput
                      value={v}
                      onChange={setV}
                      disabled={busy}
                      accept={f.accept}
                      hidePreview={f.hidePreview}
                    />
                  </div>
                )
              }
              if (f.type === 'gallery') {
                return (
                  <div key={f.key} className={`form-row${f.full ? ' full' : ''}`}>
                    <span className="form-label">{label}</span>
                    <GalleryInput value={v} onChange={setV} disabled={busy} />
                  </div>
                )
              }
              if (f.type === 'multiselect') {
                let selected: string[] = []
                try { const p = JSON.parse(v || '[]'); selected = Array.isArray(p) ? p.map((x) => String(x)) : [] } catch { selected = [] }
                const toggle = (opt: string) => {
                  const next = selected.includes(opt) ? selected.filter((s) => s !== opt) : [...selected, opt]
                  setV(JSON.stringify(next))
                }
                return (
                  <div key={f.key} className={`form-row${f.full ? ' full' : ''}`}>
                    <span className="form-label">{label}</span>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
                      {(f.options ?? []).map((opt) => (
                        <label key={opt} style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                          <input type="checkbox" checked={selected.includes(opt)} disabled={busy} onChange={() => toggle(opt)} />
                          <span>{statusLabel(opt)}</span>
                        </label>
                      ))}
                    </div>
                  </div>
                )
              }
              if (f.type === 'textarea') {
                return (
                  <label key={f.key} className={`form-row${f.full ? ' full' : ''}`}>
                    <span className="form-label">{label}{f.required && <span className="req">*</span>}</span>
                    <textarea
                      ref={ref as React.RefObject<HTMLTextAreaElement>}
                      rows={f.rows ?? 3}
                      value={v}
                      placeholder={f.placeholder}
                      disabled={busy}
                      dir={dir}
                      onChange={(e) => setV(e.target.value)}
                    />
                  </label>
                )
              }
              if (f.type === 'select') {
                return (
                  <label key={f.key} className="form-row">
                    <span className="form-label">{label}{f.required && <span className="req">*</span>}</span>
                    <select
                      ref={ref as React.RefObject<HTMLSelectElement>}
                      value={v}
                      disabled={busy}
                      onChange={(e) => setV(e.target.value)}
                    >
                      {(f.options ?? []).map((opt) => (
                        <option key={opt} value={opt}>{f.optionLabels?.[opt] ?? statusLabel(opt)}</option>
                      ))}
                    </select>
                  </label>
                )
              }
              return (
                <label key={f.key} className="form-row">
                  <span className="form-label">{label}{f.required && <span className="req">*</span>}</span>
                  <input
                    ref={ref as React.RefObject<HTMLInputElement>}
                    type={f.type === 'number' ? 'number' : f.type === 'date' ? 'date' : f.type === 'password' ? 'password' : 'text'}
                    autoComplete={f.type === 'password' ? 'new-password' : undefined}
                    value={v}
                    placeholder={f.placeholder}
                    disabled={busy}
                    dir={dir}
                    onChange={(e) => setV(e.target.value)}
                  />
                </label>
              )
            })}
          </div>
        </div>
        <div className="modal-foot">
          <button className="secondary" onClick={onClose} disabled={busy}>{t('common.cancel')}</button>
          <button onClick={handleSave} disabled={busy}>
            {busy ? t('common.saving') : (saveLabel ?? (mode === 'create' ? t('common.create') : t('common.save_changes')))}
          </button>
        </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
