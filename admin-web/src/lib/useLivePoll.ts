// Phase 27 — visibility-aware polling hook for admin pages.
//
// Call from a page that needs to auto-refresh while the admin has the
// tab open. Pauses while the tab is hidden (no point burning Postgres
// queries when nobody's looking), and refreshes immediately when the
// admin returns focus so they see fresh data without waiting for the
// next interval.
//
// Mirrors the Flutter side's RealtimePollingMixin pattern. Same 5s
// default cadence — tune slower (10–15s) for dashboards / lists that
// don't change minute-to-minute.

import { useEffect, useRef } from 'react'

interface Options {
  /** When false, the hook does nothing. Default true. */
  enabled?: boolean
  /**
   * If true, runs `tick` once immediately when the hook mounts in
   * addition to the periodic schedule. Most pages already fetch on
   * mount via their own useEffect, so this defaults to false.
   */
  immediate?: boolean
}

/**
 * Run `tick` every `intervalMs`, paused while the document is hidden.
 *
 * `tick` does not need to be stable — the hook stores it in a ref so
 * the interval keeps using the latest closure without re-creating the
 * timer when deps inside `tick` change.
 *
 * Returns nothing — purely side-effecting.
 */
export function useLivePoll(
  tick: () => void | Promise<void>,
  intervalMs: number,
  opts: Options = {},
): void {
  const { enabled = true, immediate = false } = opts

  // Stash the latest tick in a ref so we don't have to rebuild the
  // interval every time the consuming component re-renders.
  const tickRef = useRef(tick)
  tickRef.current = tick

  useEffect(() => {
    if (!enabled) return

    let cancelled = false
    let inFlight = false

    const runTick = async () => {
      if (cancelled || inFlight || document.hidden) return
      inFlight = true
      try {
        await tickRef.current()
      } catch {
        // Swallow — next interval retries. Errors should be reflected
        // in component state by the caller's fetch implementation.
      } finally {
        inFlight = false
      }
    }

    // Optional immediate fire — most callers do their own first-load
    // fetch separately, so this is off by default.
    if (immediate) void runTick()

    const handle = window.setInterval(runTick, intervalMs)

    // Refresh as soon as the admin returns to the tab.
    const onVisibility = () => {
      if (!document.hidden) void runTick()
    }
    document.addEventListener('visibilitychange', onVisibility)

    return () => {
      cancelled = true
      window.clearInterval(handle)
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [intervalMs, enabled, immediate])
}
