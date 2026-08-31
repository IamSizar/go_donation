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

import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { describeError } from '../lib/api'
import { useI18n, useStatusLabel } from '../lib/i18n'
import FileInput from './FileInput'
import type { ShapeKey } from './CropDialog'
import GalleryInput from './GalleryInput'
import { canonicalPhone, isRedactedContact, stripPhoneFormatting } from '../lib/phone'

export type FieldType = 'text' | 'textarea' | 'number' | 'date' | 'select' | 'file' | 'gallery' | 'multiselect' | 'password'

export type FieldSpec = {
  key: string                  // JSON key sent to backend + initial values key
  label: string                // shown above the input (English fallback)
  labelKey?: string            // i18n key; when set, resolved via t() instead of `label`
  type: FieldType
  options?: string[]           // for type='select'
  optionLabels?: Record<string, string> // for type='select': value → display label (else statusLabel(value))
  placeholder?: string
  // B6 — the last English left in the Arabic dashboard was the grey hint text
  // inside empty boxes: `placeholder` was rendered raw while `label` had gone
  // through `labelKey` since Phase 19. Same shape as labelKey — when set, it
  // wins over the literal.
  //
  // Format hints that carry no English ('IQD', '0', 'YYYY-MM-DD', a JSON
  // sample, a URL sample) deliberately keep the bare `placeholder` — there is
  // nothing in them to translate.
  placeholderKey?: string
  rows?: number                // for textarea
  required?: boolean           // disallow empty on save
  dir?: 'ltr' | 'rtl' | 'auto' // text direction hint (rtl for Arabic / Kurdish)
  // For type='file': optional accept string (defaults to 'image/*' inside FileInput)
  accept?: string
  // For type='file': hide the preview thumbnail (e.g. for PDFs)
  hidePreview?: boolean
  // For type='file' (#20): offer the crop step. Defaults to on — every file
  // field in the dashboard today holds an image. Pass a ShapeKey to pin the
  // crop to one shape (e.g. 'square' for an avatar), or false to skip it for
  // a field that holds a document.
  crop?: boolean | ShapeKey
  // Force a field to take the full grid width regardless of column layout
  full?: boolean
  // E7 — mark a field as holding a phone number so the modal cleans it before
  // it is sent, instead of every page remembering to. Two strengths:
  //
  //   'contact' — a number that is only ever read by a human (a partner's
  //               office line, a City Guide place). Spaces, bidi marks and
  //               human separators are stripped; nothing else is touched.
  //   'login'   — the number the account SIGNS IN with (users.phone). Also
  //               reduced to the canonical "<dial code><national>" the DB
  //               stores everywhere else, because sign-in looks the row up by
  //               that exact string — a number saved in any other shape locks
  //               the person out. Falls back to the stripped value when the
  //               input can't be read as a phone number at all, so the
  //               server's own validation still gets to answer.
  phone?: 'contact' | 'login'
  // H10 — this field's value came back REDACTED, because the operator does not
  // hold "Sensitive contact data". The control renders disabled with an
  // explanation, and buildPatch never sends it.
  //
  // WHY THE FIELD IS NOT SIMPLY LEFT EDITABLE. The value in the box is
  // "••••03". Typing over it is the natural thing to do and there is no way to
  // do it correctly: the operator cannot see what they are replacing. Leaving
  // it editable also puts a mask one keystroke away from `users.phone`, the
  // column sign-in resolves accounts by — the server refuses that write
  // (backend/.../admin_contact_write_guard.go), but a refusal the operator
  // cannot act on is a dead end, not a safeguard. Seeing the value is a
  // precondition for changing it; whoever needs to change it needs the
  // permission, which a Super-Admin grants on الصلاحيات.
  readOnly?: boolean
  // The i18n key of the section this field belongs to. When a field carries
  // one, the modal draws a full-width heading each time the value CHANGES down
  // the list, so a long form reads as the sections of the form it mirrors
  // rather than as one undifferentiated run of boxes. Optional: a page that
  // declares no sections renders exactly as it did before.
  section?: string
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
  // A caller that has to FETCH the row before the form can be filled in (the
  // Users page reads the full 104-column profile from the detail endpoint)
  // hands the wait to the modal, so the four async states live in one place
  // instead of in each page: skeleton while `loading`, a friendly error with
  // Retry while `loadError`, and the form otherwise. A caller that already has
  // its values passes none of these and the modal behaves exactly as before.
  loading?: boolean
  loadError?: string | null
  onRetry?: () => void
}

function toInputValue(v: unknown): string {
  if (v === null || v === undefined) return ''
  return typeof v === 'string' ? v : String(v)
}

// E7 — the cleaned form of what the admin typed into a phone field, per the
// field's declared strength. Non-phone fields pass through untouched.
function cleanFieldValue(f: FieldSpec, raw: string): string {
  if (!f.phone) return raw
  const stripped = stripPhoneFormatting(raw)
  if (f.phone === 'contact') return stripped
  return canonicalPhone(raw) || stripped
}

export default function EditModal({ open, title, initial, fields: declaredFields, onSave, onClose, mode = 'edit', saveLabel, loading = false, loadError = null, onRetry }: Props) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()

  // H10 — a field whose CURRENT value arrived redacted is locked, wherever it
  // appears. Decided from the VALUE the server actually sent rather than from
  // the caller's belief about its own permissions, which is what makes this
  // correct with no per-page list to maintain:
  //
  //   • the pages that show personal contact data get the lock automatically;
  //   • the pages that show the ORGANISATION'S own numbers (Partners, City
  //     Guide) never do, because those values are never redacted;
  //   • it is right during the window before the permission matrix has loaded,
  //     and right again if a Super-Admin changes the permission mid-session.
  //
  // Only in edit mode: a create form starts empty, so there is nothing hidden
  // to protect and no reason to disable the box.
  const fields = useMemo(
    () =>
      declaredFields.map((f) =>
        mode === 'edit' && !f.readOnly && isRedactedContact(initial[f.key]) ? { ...f, readOnly: true } : f,
      ),
    [declaredFields, initial, mode],
  )

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
      // H10 — a read-only field is never part of the patch. The control is
      // disabled, so this is belt-and-braces: it also covers a caller that
      // seeds `initial` with a redacted value and a field list that changes
      // under it (the pages poll, and `fields` is rebuilt on every render).
      if (f.readOnly) continue
      // E7 — clean BOTH sides before comparing, so re-typing the same number
      // with different spacing counts as "unchanged" and no pointless write is
      // sent, while a genuine edit is sent in the cleaned form.
      const next = cleanFieldValue(f, values[f.key] ?? '')
      const before = cleanFieldValue(f, initialStrings[f.key] ?? '')
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
      // H10 — a required field that is also read-only must not block the save.
      // The phone box is `required`, so without this skip an operator who
      // cannot see the number could not save ANY other change on the row.
      if (f.readOnly) continue
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
          {loading ? (
            /* Skeleton, not a spinner: it mirrors the form's own row shape, so
               the boxes fill in rather than pop in. */
            <div className="form-grid" aria-busy="true" aria-label={t('common.loading')}>
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="form-row">
                  <span className="skeleton-line" style={{ width: '40%', height: 12, display: 'block', marginBottom: 8 }} />
                  <span className="skeleton-line" style={{ width: '100%', height: 32, display: 'block' }} />
                </div>
              ))}
            </div>
          ) : loadError ? (
            /* A dead-end error screen is a bug: always offer the way out. */
            <div className="error-box">
              <p style={{ margin: 0 }}>{loadError}</p>
              {onRetry && (
                <button className="secondary" style={{ marginBlockStart: 12 }} onClick={onRetry}>
                  {t('common.retry')}
                </button>
              )}
            </div>
          ) : (
          <div className="form-grid">
            {fields.map((f, i) => {
              // A heading is emitted whenever this field's section differs from
              // the previous field's, so a caller declares its sections by the
              // ORDER of its field list and never has to nest it.
              const heading =
                f.section && f.section !== fields[i - 1]?.section ? (
                  <div className="form-row full">
                    <h3 className="form-label" style={{ margin: 0, fontSize: '0.95rem' }}>
                      {t(f.section)}
                    </h3>
                  </div>
                ) : null
              const body = (() => {
              const v = values[f.key] ?? ''
              const setV = (next: string) => setValues((m) => ({ ...m, [f.key]: next }))
              const label = f.labelKey ? t(f.labelKey) : f.label
              const placeholder = f.placeholderKey ? t(f.placeholderKey) : f.placeholder
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
                      crop={f.crop ?? true}
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
                      placeholder={placeholder}
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
                  <span className="form-label">{label}{f.required && !f.readOnly && <span className="req">*</span>}</span>
                  <input
                    ref={ref as React.RefObject<HTMLInputElement>}
                    type={f.type === 'number' ? 'number' : f.type === 'date' ? 'date' : f.type === 'password' ? 'password' : 'text'}
                    autoComplete={f.type === 'password' ? 'new-password' : undefined}
                    // E7 — a phone gets the number pad on a touch device and,
                    // in a browser that has autofill, the right suggestion.
                    inputMode={f.phone ? 'tel' : undefined}
                    value={v}
                    placeholder={placeholder}
                    disabled={busy || !!f.readOnly}
                    // A phone number always reads left-to-right, whatever the
                    // dashboard's direction — the same reason formatPhone
                    // isolates it on the display side (E1).
                    dir={f.phone ? 'ltr' : dir}
                    onChange={(e) => setV(e.target.value)}
                    // E7 — strip the spaces the moment the admin leaves the
                    // box, so what they see is what will be stored rather than
                    // a silent rewrite at save time. Deliberately only the
                    // spacing: leaving the field is not the moment to rewrite
                    // "0750…" into "964750…" under their cursor — buildPatch
                    // does the canonical step when they actually save.
                    onBlur={f.phone && !f.readOnly ? (e) => setV(stripPhoneFormatting(e.target.value)) : undefined}
                  />
                  {/* H10 — say WHY the box is dead. A disabled control with no
                      explanation reads as a broken screen, and the operator
                      has an action available to them: ask for the permission. */}
                  {f.readOnly && <span className="form-hint">{t('hint.contact_hidden')}</span>}
                </label>
              )
              })()
              return (
                <Fragment key={f.key}>
                  {heading}
                  {body}
                </Fragment>
              )
            })}
          </div>
          )}
        </div>
        <div className="modal-foot">
          <button className="secondary" onClick={onClose} disabled={busy}>{t('common.cancel')}</button>
          <button onClick={handleSave} disabled={busy || loading || !!loadError}>
            {busy ? t('common.saving') : (saveLabel ?? (mode === 'create' ? t('common.create') : t('common.save_changes')))}
          </button>
        </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
