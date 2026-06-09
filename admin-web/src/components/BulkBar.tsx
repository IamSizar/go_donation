// BulkBar — sticky action bar that appears at the bottom of the screen when
// the admin has selected one or more rows in a list. Lets them set a single
// status across all selected rows in one click. Each row PATCH/POST happens
// in parallel; the toast shows succeeded / failed counts after they all
// settle.
//
// The bar is intentionally generic so every list page that has a status
// column can wire it the same way:
//
//   <BulkBar
//     count={selected.size}
//     allowed={['active','hidden']}
//     onApply={async (status) => {
//       await Promise.allSettled([...selected].map((id) =>
//         api.post(`/api/admin/partners/${id}/status`, { status })))
//     }}
//     onClear={() => setSelected(new Set())}
//   />

import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { describeError } from '../lib/api'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'

type Props = {
  count: number
  allowed: readonly string[] | string[]
  // onApply runs the status mutation for all selected ids. It must NOT throw —
  // wrap individual row calls in Promise.allSettled and return {ok, fail}.
  onApply: (status: string) => Promise<{ ok: number; fail: number }>
  onClear: () => void
  // Optional bulk-delete: if provided, a red "Delete N" button is rendered
  // alongside the Apply button. Same contract — returns {ok, fail} after
  // all the per-row DELETEs settle.
  onDelete?: () => Promise<{ ok: number; fail: number }>
  // Label shown next to the count, e.g. "partners selected".
  noun?: string
}

export default function BulkBar({ count, allowed, onApply, onClear, onDelete, noun = 'rows' }: Props) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const [status, setStatus] = useState<string>(allowed[0] ?? '')
  const [busy, setBusy] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const toast = useToast()

  // The bar conditionally renders; AnimatePresence ensures the exit animation
  // plays when the selection drops to zero.

  async function apply() {
    if (!status || busy) return
    setBusy(true)
    try {
      const { ok, fail } = await onApply(status)
      if (fail === 0) toast.success(t('bulk.updated', { ok, noun, status }))
      else if (ok === 0) toast.error(t('bulk.mixed', { ok: 0, fail }))
      else toast.info(t('bulk.mixed', { ok, fail }))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusy(false)
    }
  }

  async function doDelete() {
    if (!onDelete || busy) return
    setConfirmDelete(false)
    setBusy(true)
    try {
      const { ok, fail } = await onDelete()
      if (fail === 0) toast.success(t('bulk.deleted', { ok, noun }))
      else if (ok === 0) toast.error(t('bulk.del_mixed', { ok: 0, fail }))
      else toast.info(t('bulk.del_mixed', { ok, fail }))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <AnimatePresence>
        {count > 0 && (
      <motion.div
        className="bulk-bar"
        role="region"
        aria-label={t('common.bulk_actions')}
        // Note: .bulk-bar in CSS is left:50%; the centering happens via
        // translateX(-50%). framer-motion writes to `transform` for `y`, so
        // we apply both inline: the static -50% shift plus the animated y.
        // Using `transformTemplate` keeps both in the right order.
        transformTemplate={(_, generated) => `translateX(-50%) ${generated}`}
        initial={{ opacity: 0, y: 24, scale: 0.96 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={{ opacity: 0, y: 16, scale: 0.96, transition: { duration: 0.18 } }}
        transition={{ type: 'spring', stiffness: 280, damping: 24 }}
      >
        <span><strong>{count}</strong> {noun} {t('common.selected')}</span>
        <select value={status} onChange={(e) => setStatus(e.target.value)} disabled={busy} style={{ width: 'auto' }}>
          {allowed.map((s) => (
            <option key={s} value={s}>{statusLabel(s)}</option>
          ))}
        </select>
        <button onClick={apply} disabled={busy || !status}>{busy ? t('common.applying') : t('common.apply')}</button>
        {onDelete && (
          <button className="danger" onClick={() => setConfirmDelete(true)} disabled={busy}>
            {t('common.delete')} {count}
          </button>
        )}
        <button className="secondary" onClick={onClear} disabled={busy}>{t('common.clear')}</button>
      </motion.div>
        )}
      </AnimatePresence>
      {confirmDelete && (
        <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) setConfirmDelete(false) }}>
          <div className="modal-card" role="alertdialog" aria-modal="true" style={{ width: 'min(440px, 92vw)' }}>
            <div className="modal-head"><h2>{t('bulk.confirm_title', { count, noun })}</h2></div>
            <div className="modal-body">
              <p style={{ margin: 0 }}>{t('bulk.confirm_body')}</p>
            </div>
            <div className="modal-foot">
              <button className="secondary" onClick={() => setConfirmDelete(false)}>{t('common.cancel')}</button>
              <button className="danger" onClick={doDelete}>{t('common.delete')} {count}</button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
