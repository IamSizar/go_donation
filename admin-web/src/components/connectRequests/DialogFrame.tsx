/**
 * DialogFrame — the modal shell the connect-request Approve and Decline
 * dialogs share: backdrop, card, heading with a close button, a scrolling
 * body and a footer, wrapped in one <form>.
 *
 * It mirrors CreateGroupDialog's shell (Phase 6a) exactly: the same
 * framer-motion enter/exit, Escape and focus trapping through
 * useDialogKeyboard, and a backdrop that closes on mousedown only, so a text
 * selection that ends outside the card never throws a draft away. While
 * `busy`, neither Escape, the backdrop nor the close button can dismiss it.
 *
 * The parent mounts it inside AnimatePresence only while open.
 */
import { motion } from 'framer-motion'
import { useId, useRef, type FormEvent, type ReactNode } from 'react'
import { useDialogKeyboard } from '../chatGroups/useDialogKeyboard'
import { useI18n } from '../../lib/i18n'

type Props = {
  title: string
  /** A request is in flight: every way to dismiss is locked. */
  busy: boolean
  onClose: () => void
  onSubmit: (event: FormEvent) => void
  /** The card's width, e.g. 'min(720px, 94vw)'. */
  width: string
  children: ReactNode
  /** The footer's buttons and hint. */
  footer: ReactNode
}

export default function DialogFrame({ title, busy, onClose, onSubmit, width, children, footer }: Props) {
  const { t } = useI18n()
  const headingId = useId()
  const cardRef = useRef<HTMLDivElement>(null)
  useDialogKeyboard(cardRef, busy ? null : onClose)

  return (
    <motion.div
      className="modal-overlay"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.18 }}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget && !busy) onClose()
      }}
    >
      <motion.div
        ref={cardRef}
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-labelledby={headingId}
        style={{ width }}
        initial={{ opacity: 0, scale: 0.94, y: 12 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.96, y: 8 }}
        transition={{ type: 'spring', stiffness: 320, damping: 28 }}
      >
        <form
          onSubmit={onSubmit}
          noValidate
          style={{ display: 'flex', flexDirection: 'column', flex: '1 1 auto', minHeight: 0 }}
        >
          <div className="modal-head">
            <h2 id={headingId}>{title}</h2>
            <button type="button" className="icon" onClick={onClose} disabled={busy} aria-label={t('common.close')}>
              ×
            </button>
          </div>
          <div className="modal-body stack">{children}</div>
          <div className="modal-foot" style={{ alignItems: 'center' }}>
            {footer}
          </div>
        </form>
      </motion.div>
    </motion.div>
  )
}
