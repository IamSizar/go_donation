// pendingCounts.tsx — React context + hook for the sidebar's live badges.
//
// Phase 16. Polls /api/admin/pending-counts every 5 seconds and exposes the
// counts to anything that mounts. The provider is mounted once at the app
// shell level so every page (sidebar, dashboard, future banner widgets)
// shares ONE polling timer regardless of how many components consume it.
//
// Why polling and not WebSocket / SSE?
//   • The endpoint is sub-millisecond, the payload is ~90 bytes.
//   • One in-flight request every 5 seconds is invisible at this scale.
//   • Zero infrastructure: no pg_notify trigger, no listener goroutine,
//     no SSE reconnect logic. Upgrade-path is wide open later: swap the
//     setInterval for an EventSource and the rest of the app is unchanged.

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { api } from './api'
import { useAuth } from './auth'

// Mirrors backend `handlers.PendingCounts`. Total is server-derived so the
// client never has to re-sum (avoids the bug where adding a new section to
// the backend leaves the client total stale).
export type PendingCounts = {
  donations: number
  sponsorships: number
  beneficiary: number
  marketplace: number
  support: number
  in_kind: number
  volunteers: number
  mission_signups: number   // Phase 21
  marriage: number
  registrations: number     // new-user signups awaiting approval
  total: number
}

const EMPTY: PendingCounts = {
  donations: 0,
  sponsorships: 0,
  beneficiary: 0,
  marketplace: 0,
  support: 0,
  in_kind: 0,
  volunteers: 0,
  mission_signups: 0,
  marriage: 0,
  registrations: 0,
  total: 0,
}

// POLL_MS is intentionally per the product decision (5 sec). If you change
// it, change the docstring on the backend endpoint too.
const POLL_MS = 5_000

type Ctx = {
  counts: PendingCounts
  loading: boolean
  /** Manual refresh — useful right after a mutation that we know moves a
   *  count, so the badge updates without waiting for the next tick. */
  refresh: () => void
}

const PendingCountsContext = createContext<Ctx>({
  counts: EMPTY,
  loading: false,
  refresh: () => {},
})

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
        // eslint-disable-next-line no-console
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

// usePendingCounts — read-only hook for any component that needs a count.
// Returns the full record, the per-section number, plus `refresh()` if the
// caller knows it just changed something (e.g. an admin approved a donation).
export function usePendingCounts(): Ctx {
  return useContext(PendingCountsContext)
}
