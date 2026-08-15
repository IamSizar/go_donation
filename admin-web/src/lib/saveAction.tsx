// saveAction — the wiring behind the shared حفظ button in the top action bar.
//
// F3. The client asked for one fixed bar in every section carrying رجوع /
// التالي / تحديث / حفظ. The bar was built and the first three work, but حفظ
// fired `window.dispatchEvent(new CustomEvent('app:save'))` and NOTHING in the
// dashboard ever listened for it — searching all of admin-web/src found the
// string only at the line that dispatched it. So the button was live, styled as
// the primary action, and did nothing on every page in the product.
//
// Two things had to be true to fix that honestly:
//
//   1. Where a page really does have a single "save this page" action, the bar
//      button must run it. That is what `useRegisterSaveAction` does.
//   2. Where a page has NO page-level save — every list page, where editing
//      happens inside a row modal that has its own save button — the bar button
//      must stop pretending. Nothing registers, so it renders disabled.
//
// A global event could not deliver (2): a fire-and-forget dispatch cannot tell
// the sender whether anyone was listening, which is precisely how the button
// ended up looking functional for so long. A registry can, because the bar can
// see whether a handler exists.
//
// Deliberately NOT wired: pages carrying SEVERAL independent forms (إعدادات
// النظام has five, the category managers save per row). One button cannot mean
// "save all of them" without inventing a meaning the client did not ask for and
// firing several unrelated writes from one click. Those pages keep their own
// per-form buttons and the bar's حفظ stays disabled there — which is the
// truthful state, not a gap.

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'

/** What a page hands over: run the page's save. May be async. */
export type SaveHandler = () => void | Promise<unknown>

type SaveActionCtx = {
  /** The handler the page on screen registered, or null when there is none. */
  handler: SaveHandler | null
  /** True while that handler is running, so the bar can disable itself. */
  busy: boolean
  /** Page side. Passing null clears the registration. */
  register: (h: SaveHandler | null) => void
  setBusy: (b: boolean) => void
}

const SaveActionContext = createContext<SaveActionCtx | null>(null)

export function SaveActionProvider({ children }: { children: ReactNode }) {
  const [handler, setHandler] = useState<SaveHandler | null>(null)
  const [busy, setBusy] = useState(false)

  // Stored in a state cell that holds the function itself, so `register` has to
  // wrap it — React treats a bare function passed to a setter as an updater.
  const register = useCallback((h: SaveHandler | null) => {
    setHandler(() => h)
    setBusy(false)
  }, [])

  const value = useMemo<SaveActionCtx>(
    () => ({ handler, busy, register, setBusy }),
    [handler, busy, register],
  )
  return <SaveActionContext.Provider value={value}>{children}</SaveActionContext.Provider>
}

/**
 * Page side: offer this page's save to the shared bar button.
 *
 * The handler is kept in a ref and only a stable wrapper is registered, so a
 * page can pass a fresh closure on every render (the normal case — the handler
 * reads form state) without re-registering in a loop.
 *
 * @param handler the page's save, or null/undefined when it currently has none
 *                (still loading, read-only for this user, nothing changed).
 */
export function useRegisterSaveAction(handler: SaveHandler | null | undefined) {
  const ctx = useContext(SaveActionContext)
  const latest = useRef<SaveHandler | null | undefined>(handler)
  // Written in an effect rather than during render: a ref assigned while
  // rendering is a lint error and, under StrictMode's double render, an easy
  // way to store a closure from a render that was thrown away. This effect has
  // no dependency array on purpose — it must refresh after EVERY render, since
  // the point is to keep the newest closure (and therefore the newest form
  // state) reachable.
  useEffect(() => { latest.current = handler })

  // Only the PRESENCE of a handler is a dependency — swapping one closure for
  // another must not churn the provider's state.
  const available = !!handler

  useEffect(() => {
    if (!ctx) return
    if (!available) {
      ctx.register(null)
      return
    }
    ctx.register(() => latest.current?.())
    return () => ctx.register(null)
    // ctx.register is stable (useCallback with no deps).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [available])
}

/** Bar side: the handler to run, whether one exists, and whether it is running. */
export function useSaveAction(): { save: () => void; canSave: boolean; busy: boolean } {
  const ctx = useContext(SaveActionContext)
  const save = useCallback(() => {
    if (!ctx?.handler) return
    const result = ctx.handler()
    // Reflect an async save in the button. A handler that throws is the page's
    // to report — it already owns the toast — but the button must not stay
    // stuck on "saving" because of it.
    if (result && typeof (result as Promise<unknown>).finally === 'function') {
      ctx.setBusy(true)
      void (result as Promise<unknown>).finally(() => ctx.setBusy(false))
    }
  }, [ctx])
  return { save, canSave: !!ctx?.handler, busy: !!ctx?.busy }
}
