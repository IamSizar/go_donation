// ConfirmDialog — small modal used by every "Delete" action in Phase 13.
//
// Caller controls `open` and supplies `onConfirm` (returns Promise so we can
// show a spinner) and `onCancel`. The "Delete" button gets a danger style
// (red background) so it's visually distinct from the regular Save buttons.
//
// Esc and click-outside cancel. The confirm button focuses on open.

import { useEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'

type Props = {
  open: boolean
  title: string
  message?: string
  confirmLabel?: string
  cancelLabel?: string
  // Optional second confirmation gate: shows a text input the admin must type
  // exactly to enable the confirm button. Use for high-stakes deletes.
  typeToConfirm?: string
  onConfirm: () => Promise<unknown>
  onCancel: () => void
}

export default function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  cancelLabel,
  typeToConfirm,
  onConfirm,
  onCancel,
}: Props) {
  const { t } = useI18n()
  const finalConfirmLabel = confirmLabel ?? t('common.delete')
  const finalCancelLabel = cancelLabel ?? t('common.cancel')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [typed, setTyped] = useState('')
  const confirmRef = useRef<HTMLButtonElement | null>(null)

  useEffect(() => {
    if (!open) return
    setBusy(false)
    setErr(null)
    setTyped('')
    setTimeout(() => confirmRef.current?.focus(), 50)
  }, [open])

  useEffect(() => {
    if (!open) return
    function handle(e: KeyboardEvent) {
      if (e.key === 'Escape' && !busy) onCancel()
    }
    window.addEventListener('keydown', handle)
    return () => window.removeEventListener('keydown', handle)
  }, [open, busy, onCancel])

  // Always render the AnimatePresence wrapper; the open guard lives inside so
  // the exit animation has time to play before unmount.

  const typedOK = !typeToConfirm || typed.trim() === typeToConfirm

  async function go() {
    if (busy || !typedOK) return
    setBusy(true)
    setErr(null)
    try {
      await onConfirm()
    } catch (e) {
      setErr(describeError(e))
      setBusy(false)
      return
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
            if (e.target === e.currentTarget && !busy) onCancel()
          }}
        >
          <motion.div
            className="modal-card"
            role="alertdialog"
            aria-modal="true"
            style={{ width: 'min(440px, 92vw)' }}
            initial={{ opacity: 0, scale: 0.94, y: 12 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96, y: 8 }}
            transition={{ type: 'spring', stiffness: 320, damping: 28 }}
          >
        <div className="modal-head">
          <h2>{title}</h2>
        </div>
        <div className="modal-body">
          {message && <p style={{ margin: '0 0 12px 0' }}>{message}</p>}
          {err && <div className="error-box" style={{ marginBottom: 12 }}>{err}</div>}
          {typeToConfirm && (
            <label className="form-row">
              <span className="form-label">{t('common.type_to_confirm_pre')} <code>{typeToConfirm}</code> {t('common.type_to_confirm_post')}</span>
              <input
                type="text"
                value={typed}
                onChange={(e) => setTyped(e.target.value)}
                disabled={busy}
                autoFocus
              />
            </label>
          )}
        </div>
        <div className="modal-foot">
          <button className="secondary" onClick={onCancel} disabled={busy}>{finalCancelLabel}</button>
          <button ref={confirmRef} className="danger" onClick={go} disabled={busy || !typedOK}>
            {busy ? t('common.deleting') : finalConfirmLabel}
          </button>
        </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
