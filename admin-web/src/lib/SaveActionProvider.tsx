// SaveActionProvider — holds the save handler the page on screen registered.
//
// Split out of saveAction.tsx so that file can keep exporting the context and
// the two hooks without mixing them with a component export: fast refresh
// recreates a module's bindings on every edit, so a context declared beside a
// component would be swapped for a brand-new one and every Provider/consumer
// pair would come apart mid-session (react-refresh/only-export-components).
// Behaviour is unchanged.

import { useCallback, useMemo, useState, type ReactNode } from 'react'
import { SaveActionContext, type SaveActionCtx, type SaveHandler } from './saveAction'

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
