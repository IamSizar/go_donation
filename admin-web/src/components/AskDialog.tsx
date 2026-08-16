// AskDialog — the in-app modal that replaces window.prompt() / window.confirm().
//
// WHY THIS EXISTS. Every PIN step-up, verification-code entry and delete
// confirmation in this dashboard used to be a NATIVE browser dialog. Browsers
// are allowed to refuse those — sandboxed frames, some embedded contexts, and
// increasingly ordinary sessions answer prompt() with "prompt() is not
// supported" and hand back nothing at all. When that happens the gate in front
// of the action is the thing that breaks: the reported symptom was an operator
// who could not change a user's type AT ALL, because the PIN prompt guarding
// the change never appeared. This dialog is drawn by the app, so the browser
// has no say in whether it opens.
//
// It is deliberately dumb. It collects one answer and resolves. Verification,
// error toasts and busy states stay with the callers — exactly where they were
// while the native dialogs did the asking — so swapping the dialog changed the
// dialog and nothing else.
//
// Visual language is the dashboard's existing modal (.modal-overlay /
// .modal-card / .modal-head / .modal-body / .modal-foot plus the framer-motion
// spring), the same one EditModal and ConfirmDialog already draw. Nothing new
// was invented here.
//
// Accessibility: this replaces a NATIVE modal, so it must not be less capable
// than one. Focus moves in on open, is trapped while open, and returns to the
// element that opened the dialog on close. Escape and the backdrop cancel.

import { useEffect, useRef, type FormEvent } from 'react'
import { motion } from 'framer-motion'
import { useI18n } from '../lib/i18n'
import type { DialogAnswer, DialogRequest } from '../lib/dialogs'

// Everything inside the card that can hold focus. Used by the Tab trap below.
const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ')

type Props = {
  request: DialogRequest
  /** Called exactly once with the operator's answer — null/false on cancel. */
  onSettle: (answer: DialogAnswer) => void
}

export default function AskDialog({ request, onSettle }: Props) {
  const { t } = useI18n()
  const cardRef = useRef<HTMLDivElement | null>(null)
  const inputRef = useRef<HTMLInputElement | null>(null)
  const confirmRef = useRef<HTMLButtonElement | null>(null)
  // The element that had focus when we opened, so we can hand it back. Captured
  // in a ref (not state) because it must survive every render untouched.
  const openerRef = useRef<Element | null>(null)

  const isText = request.kind === 'text'
  const destructive = request.destructive === true

  // ─── Labels ───
  // Resolved here rather than at the call sites so lib/api.ts (which has no
  // hooks) can ask for a dialog without carrying button text around. Every key
  // used below already exists in all four locales — see common.* in locales/.
  const title = request.title ?? (destructive ? t('common.delete') : t('common.confirm'))
  const confirmLabel =
    request.confirmLabel ?? (destructive ? t('common.delete') : t('common.confirm'))
  const cancelLabel = request.cancelLabel ?? t('common.cancel')

  // ─── Focus: move in on open, hand back on close ───
  useEffect(() => {
    openerRef.current = document.activeElement
    // A text ask starts in its input; a confirm starts on the confirm button,
    // matching ConfirmDialog and the native dialogs these replace (so Enter
    // does the obvious thing). Cancel stays the safe default in the sense that
    // matters: every DISMISSAL path — Escape, backdrop, the Cancel button —
    // resolves as a cancel and applies nothing.
    const focusTimer = window.setTimeout(() => {
      if (inputRef.current) inputRef.current.focus()
      else confirmRef.current?.focus()
    }, 50)
    return () => {
      window.clearTimeout(focusTimer)
      const opener = openerRef.current
      // The opener can be gone by now (a row that re-rendered, a menu that
      // closed). Guard rather than assume it is still focusable.
      if (opener instanceof HTMLElement && document.contains(opener)) opener.focus()
    }
  }, [])

  // ─── Keyboard: Escape cancels, Tab stays inside the card ───
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.preventDefault()
        onSettle(isText ? null : false)
        return
      }
      if (e.key !== 'Tab') return
      const card = cardRef.current
      if (!card) return
      const items = Array.from(card.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))
      if (items.length === 0) return
      const first = items[0]
      const last = items[items.length - 1]
      const active = document.activeElement
      // Wrap at both ends, and pull focus back in if it has escaped the card
      // entirely (browser chrome, a stray programmatic blur).
      if (e.shiftKey && (active === first || !card.contains(active))) {
        e.preventDefault()
        last.focus()
      } else if (!e.shiftKey && (active === last || !card.contains(active))) {
        e.preventDefault()
        first.focus()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [isText, onSettle])

  // ─── Submit ───
  // A text ask resolves with whatever is in the box, INCLUDING the empty
  // string. That is not an oversight: window.prompt() distinguished "" (the
  // operator submitted nothing) from null (the operator cancelled), and callers
  // rely on the difference — one raises the "password is required" toast, and
  // common.set_password_prompt treats a blank entry as "clear the password".
  // Disabling the button on an empty box would silently delete both behaviours,
  // so the button stays live and the caller keeps deciding.
  function submit(e: FormEvent) {
    e.preventDefault()
    if (!isText) {
      onSettle(true)
      return
    }
    onSettle(inputRef.current?.value ?? '')
  }

  function cancel() {
    onSettle(isText ? null : false)
  }

  const titleId = 'ask-dialog-title'
  const messageId = 'ask-dialog-message'

  return (
    <motion.div
      className="modal-overlay ask-overlay"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.18 }}
      onMouseDown={(e) => {
        // mousedown, not click: a click that STARTED inside the card and ended
        // on the backdrop (a drag while selecting the message) must not cancel.
        if (e.target === e.currentTarget) cancel()
      }}
    >
      <motion.div
        ref={cardRef}
        className="modal-card"
        // alertdialog for a confirmation (it interrupts to ask), dialog for a
        // text entry (it interrupts to collect).
        role={isText ? 'dialog' : 'alertdialog'}
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={request.message ? messageId : undefined}
        style={{ width: 'min(440px, 92vw)' }}
        initial={{ opacity: 0, scale: 0.94, y: 12 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.96, y: 8 }}
        transition={{ type: 'spring', stiffness: 320, damping: 28 }}
      >
        <form onSubmit={submit}>
          <div className="modal-head">
            <h2 id={titleId}>{title}</h2>
          </div>
          <div className="modal-body">
            {request.message && (
              // pre-wrap because some callers build a two-paragraph message
              // with "\n\n" (the permissions OTP prompt adds a degraded-mode
              // warning underneath), which a native prompt() rendered as two
              // lines and this must too.
              <p
                id={messageId}
                style={{ margin: 0, whiteSpace: 'pre-wrap', lineHeight: 1.55 }}
              >
                {request.message}
              </p>
            )}
            {isText && (
              <label className="form-row" style={{ marginTop: request.message ? 16 : 0 }}>
                <span className="form-label">{title}</span>
                <input
                  ref={inputRef}
                  // Masked for every PIN, password and verification code. The
                  // value lives in the DOM node only — it is never put in
                  // component state, never logged, and never interpolated into
                  // an error message.
                  type={request.secret ? 'password' : 'text'}
                  inputMode={request.inputMode}
                  placeholder={request.placeholder ?? (request.secret ? '••••••••' : undefined)}
                  // A step-up asks for the operator's OWN password; letting the
                  // password manager offer it is the same affordance the
                  // PasswordGate and IdleLock inputs already give. The
                  // delivered 6-digit codes override this with 'one-time-code'.
                  autoComplete={
                    request.autoComplete ?? (request.secret ? 'current-password' : 'off')
                  }
                  spellCheck={false}
                />
              </label>
            )}
          </div>
          <div className="modal-foot">
            <button type="button" className="secondary" onClick={cancel}>
              {cancelLabel}
            </button>
            <button
              ref={confirmRef}
              type="submit"
              className={destructive ? 'danger' : 'primary'}
            >
              {confirmLabel}
            </button>
          </div>
        </form>
      </motion.div>
    </motion.div>
  )
}
