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

export type Pending = {
  id: number
  request: DialogRequest
  resolve: (answer: DialogAnswer) => void
}

let nextRequestId = 1

/** The id the next queued request takes. <DialogHost /> stamps its entries. */
export function takeRequestId(): number {
  return nextRequestId++
}

// Set by <DialogHost /> while it is mounted. Null before/after.
let enqueueRequest: ((request: DialogRequest) => Promise<DialogAnswer>) | null = null

/**
 * <DialogHost /> registers itself here on mount and clears it on unmount.
 *
 * It lives in its own module — DialogHost.tsx — because a file that exports a
 * component may not also export functions (react-refresh/only-export-
 * components), and askForText/askToConfirm are called from plain async code in
 * lib/api.ts with no hooks in sight. So the host reaches the queue through
 * this setter instead of assigning the module variable directly.
 */
export function setDialogEnqueue(
  fn: ((request: DialogRequest) => Promise<DialogAnswer>) | null,
) {
  enqueueRequest = fn
}

// ask — hands the request to the mounted host, or resolves as a cancel when
// there is no host. Cancelling is the only safe answer to "nobody can ask":
// it aborts the action instead of letting it run ungated.
function ask(request: DialogRequest, cancelled: DialogAnswer): Promise<DialogAnswer> {
  if (!enqueueRequest) {
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
