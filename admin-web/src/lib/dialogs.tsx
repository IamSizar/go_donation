// dialogs.tsx — askForText() / askToConfirm(), the promise-based, app-drawn
// replacement for window.prompt() and window.confirm().
//
// WHY. Browsers may refuse a native prompt() outright (sandboxed frames, some
// embedded contexts, and increasingly ordinary sessions), and when they do the
// call returns nothing and the whole action dies. Every PIN step-up in this
// dashboard sat behind one, so on such a browser an operator could not change
// a user's type, export a list, or restore from the Trash at all.
//
// Shape of the replacement:
//
//     const pin = await askForText({ title, message, secret: true })
//     if (pin === null) return                     // cancelled — do nothing
//
//     if (!(await askToConfirm({ message, destructive: true }))) return
//
// The return types mirror the natives EXACTLY, because callers already read
// them that way: askForText resolves to null when cancelled and to '' when the
// operator submits an empty box, and askToConfirm resolves to a boolean.
//
// Non-React callers. lib/api.ts asks for the H20 confirmation code and the H14
// unlock code from inside a plain async function with no hooks in sight. So the
// asking side is a module-level function and <DialogHost /> registers itself
// into it on mount — the same split i18n already uses between translate() and
// useI18n().

import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react'
import { AnimatePresence } from 'framer-motion'
import AskDialog from '../components/AskDialog'

// ─── Request / answer shapes ───

/** Fields both kinds of ask share. */
type CommonAsk = {
  /** Dialog heading. Defaults to t('common.confirm') inside the dialog. */
  title?: string
  /** Body text. This is the string the native prompt/confirm used to show. */
  message?: string
  /** Draw the primary button as destructive (red). Deletes and purges. */
  destructive?: boolean
  /** Override the primary button label. Defaults to Delete/Confirm. */
  confirmLabel?: string
  /** Override the cancel button label. Defaults to Cancel. */
  cancelLabel?: string
}

/** Ask the operator to type something. Resolves null when cancelled. */
export type TextAsk = CommonAsk & {
  /** Mask the input (type="password"). Every PIN, password and code sets this. */
  secret?: boolean
  placeholder?: string
  /** Keyboard hint — 'numeric' for amount and 6-digit-code fields. */
  inputMode?: 'text' | 'numeric'
  /**
   * Autofill hint. Defaults to 'current-password' for a secret ask and 'off'
   * otherwise. Pass 'one-time-code' for the delivered 6-digit codes, so a
   * password manager offers the code rather than the operator's own password.
   */
  autoComplete?: 'current-password' | 'new-password' | 'one-time-code' | 'off'
}

/** Ask the operator to approve an action. Resolves false when cancelled. */
export type ConfirmAsk = CommonAsk

export type DialogRequest =
  | (TextAsk & { kind: 'text' })
  | (ConfirmAsk & { kind: 'confirm' })

/** null/'' from a text ask, true/false from a confirm ask. */
export type DialogAnswer = string | null | boolean

// ─── The module-level asking side ───

type Pending = {
  id: number
  request: DialogRequest
  resolve: (answer: DialogAnswer) => void
}

let nextRequestId = 1

// Set by <DialogHost /> while it is mounted. Null before/after.
let enqueueRequest: ((request: DialogRequest) => Promise<DialogAnswer>) | null = null

// ask — hands the request to the mounted host, or resolves as a cancel when
// there is no host. Cancelling is the only safe answer to "nobody can ask":
// it aborts the action instead of letting it run ungated.
function ask(request: DialogRequest, cancelled: DialogAnswer): Promise<DialogAnswer> {
  if (!enqueueRequest) {
    // eslint-disable-next-line no-console
    console.error('dialogs: no <DialogHost /> is mounted — treating the ask as cancelled.')
    return Promise.resolve(cancelled)
  }
  return enqueueRequest(request)
}

/**
 * Ask the operator to type a value.
 *
 * @returns the typed string (possibly empty), or null if they cancelled —
 *          the same two outcomes window.prompt() had, so callers that
 *          distinguish "submitted nothing" from "backed out" keep working.
 */
export async function askForText(options: TextAsk): Promise<string | null> {
  const answer = await ask({ ...options, kind: 'text' }, null)
  return typeof answer === 'string' ? answer : null
}

/**
 * Ask the operator to approve an action.
 *
 * @returns true only if they pressed the confirm button. Escape, the backdrop
 *          and the cancel button all resolve false.
 */
export async function askToConfirm(options: ConfirmAsk): Promise<boolean> {
  const answer = await ask({ ...options, kind: 'confirm' }, false)
  return answer === true
}

// ─── The rendering side ───

/**
 * DialogHost — mount once at the app root, inside I18nProvider (the dialog
 * localizes its own buttons).
 *
 * Holds a FIFO queue rather than a single slot. Nothing in the app opens two
 * dialogs at once today — every caller awaits — but a dropped request would be
 * a promise that never settles, which is an await that hangs forever and a
 * frozen action. Queueing makes that unrepresentable.
 */
export function DialogHost() {
  const [queue, setQueue] = useState<Pending[]>([])
  // Guards against a double-settle (a click landing at the same time as an
  // Escape) resolving one request and dequeuing two.
  const settledIdRef = useRef<number | null>(null)

  useEffect(() => {
    enqueueRequest = (request) =>
      new Promise<DialogAnswer>((resolve) => {
        setQueue((q) => [...q, { id: nextRequestId++, request, resolve }])
      })
    return () => {
      enqueueRequest = null
    }
  }, [])

  const current = queue[0]

  const settle = useCallback(
    (answer: DialogAnswer) => {
      if (!current || settledIdRef.current === current.id) return
      settledIdRef.current = current.id
      current.resolve(answer)
      setQueue((q) => q.filter((p) => p.id !== current.id))
    },
    [current],
  )

  // AnimatePresence keeps the exit animation alive after the request leaves the
  // queue; the key makes a second queued dialog a fresh mount (fresh focus,
  // empty input) rather than a re-render of the previous one.
  return (
    <AnimatePresence>
      {current && <AskDialog key={current.id} request={current.request} onSettle={settle} />}
    </AnimatePresence>
  )
}
