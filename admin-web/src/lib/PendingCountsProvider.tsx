// PendingCountsProvider — polls /api/admin/pending-counts for the sidebar
// badges.
//
// Split out of pendingCounts.tsx so that file can keep exporting the context
// and usePendingCounts without mixing them with a component export: fast
// refresh recreates a module's bindings on every edit, so a context declared
// beside a component would be swapped for a brand-new one and every
// Provider/consumer pair would come apart mid-session (react-refresh/
// only-export-components). Behaviour is unchanged.

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { api } from './api'
import { useAuth } from './auth'
import {
  EMPTY,
  POLL_MS,
  PendingCountsContext,
  type Ctx,
  type PendingCounts,
} from './pendingCounts'

export function PendingCountsProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth()
  const [counts, setCounts] = useState<PendingCounts>(EMPTY)
  const [loading, setLoading] = useState(false)

  // Use a ref so multiple `refresh()` calls in the same tick coalesce —
  // and so we can cancel a stale request when one races with another.
  const inFlightRef = useRef<AbortController | null>(null)

  const fetchOnce = useCallback(async () => {
    // Bail if not signed in — the endpoint is admin-only and would 401.
    if (!user) return

    // Cancel any prior in-flight call.
    inFlightRef.current?.abort()
    const ac = new AbortController()
    inFlightRef.current = ac

    setLoading(true)
    try {
      const res = await api.get<PendingCounts>('/api/admin/pending-counts', {
        signal: ac.signal,
      })
      setCounts(res.data)
    } catch (err: unknown) {
      // Swallow aborts; surface other errors silently (the sidebar should
      // never hard-fail because a count poll briefly errored — the next
      // tick will retry).
      const e = err as { name?: string; code?: string }
      if (e?.name !== 'CanceledError' && e?.code !== 'ERR_CANCELED') {
        // Keep the previous counts on the screen; just log for diagnostics.
        console.warn('pending-counts poll failed:', err)
      }
    } finally {
      // Only clear the loading flag if THIS request is still the latest.
      if (inFlightRef.current === ac) setLoading(false)
    }
  }, [user])

  useEffect(() => {
    // Skip polling entirely when signed out — saves a 401 every 5 seconds.
    if (!user) {
      setCounts(EMPTY)
      return
    }
    // Immediate fetch on mount + login, then a steady tick.
    fetchOnce()
    const id = setInterval(fetchOnce, POLL_MS)
    return () => {
      clearInterval(id)
      inFlightRef.current?.abort()
    }
  }, [user, fetchOnce])

  const value = useMemo<Ctx>(
    () => ({ counts, loading, refresh: fetchOnce }),
    [counts, loading, fetchOnce],
  )

  return (
    <PendingCountsContext.Provider value={value}>
      {children}
    </PendingCountsContext.Provider>
  )
}
