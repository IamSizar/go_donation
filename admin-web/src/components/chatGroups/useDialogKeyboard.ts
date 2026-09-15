/**
 * useDialogKeyboard — keyboard behaviour for the chat-group modals.
 *
 * WHAT IT DOES
 * - On open, moves focus into the card: to the element marked
 *   `data-autofocus`, else to the first focusable element.
 * - While open, Escape calls `onEscape` (pass null to ignore Escape, e.g.
 *   while a request is in flight), and Tab stays inside the card.
 * - On close, hands focus back to whatever had it before the dialog opened.
 *
 * WHY A HOOK
 * AskDialog does the same for the app's prompt/confirm dialogs, inline in its
 * component. The chat-group forms need it too, and a form dialog must not be
 * less keyboard-capable than a confirm. Focus moves synchronously on mount,
 * not after a timer, so a delayed focus can never land in the middle of
 * someone typing.
 */
import { useEffect, useRef, type RefObject } from 'react'

/** Everything inside the card that can hold focus. */
const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ')

/** Keeps Tab and Shift+Tab cycling inside `card`. */
function trapTab(event: KeyboardEvent, card: HTMLElement | null): void {
  if (!card) return
  const items = Array.from(card.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))
  if (items.length === 0) return
  const first = items[0]
  const last = items[items.length - 1]
  const active = document.activeElement
  if (event.shiftKey && (active === first || !card.contains(active))) {
    event.preventDefault()
    last.focus()
  } else if (!event.shiftKey && (active === last || !card.contains(active))) {
    event.preventDefault()
    first.focus()
  }
}

/**
 * Wires the keyboard behaviour above to one dialog card.
 *
 * @param cardRef   the dialog card element.
 * @param onEscape  what Escape does; null to ignore it for now.
 */
export function useDialogKeyboard(cardRef: RefObject<HTMLElement | null>, onEscape: (() => void) | null): void {
  // The latest callback, read at key time, so the listener below is attached
  // once per open rather than re-attached on every render.
  const escapeRef = useRef(onEscape)
  useEffect(() => {
    escapeRef.current = onEscape
  }, [onEscape])

  useEffect(() => {
    const opener = document.activeElement
    const card = cardRef.current
    const target = card?.querySelector<HTMLElement>('[data-autofocus]') ?? card?.querySelector<HTMLElement>(FOCUSABLE_SELECTOR)
    target?.focus()

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && escapeRef.current) {
        event.preventDefault()
        escapeRef.current()
      } else if (event.key === 'Tab') {
        trapTab(event, cardRef.current)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => {
      window.removeEventListener('keydown', onKeyDown)
      // The opener can be gone by now (a list that re-rendered); guard first.
      if (opener instanceof HTMLElement && document.contains(opener)) opener.focus()
    }
  }, [cardRef])
}
