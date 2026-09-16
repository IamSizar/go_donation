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

import { createContext, useContext } from 'react'
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

export const EMPTY: PendingCounts = {
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
export const POLL_MS = 5_000

// `loading` used to sit here beside `counts`, set true at the top of every
// poll. No consumer ever read it — the badges just show the last known number
// — and keeping it meant the provider's effect writing state synchronously on
// every mount, which is what react-hooks/set-state-in-effect objects to. It is
// gone rather than faked.
export type Ctx = {
  counts: PendingCounts
  /** Manual refresh — useful right after a mutation that we know moves a
   *  count, so the badge updates without waiting for the next tick. */
  refresh: () => void
}

export const PendingCountsContext = createContext<Ctx>({
  counts: EMPTY,
  refresh: () => {},
})
// usePendingCounts — read-only hook for any component that needs a count.
// Returns the full record, the per-section number, plus `refresh()` if the
// caller knows it just changed something (e.g. an admin approved a donation).
export function usePendingCounts(): Ctx {
  return useContext(PendingCountsContext)
}
