// useUserEditProfile — loads the full profile behind the Edit-User modal.
//
// WHY A FETCH AND NOT THE LIST ROW
// The Edit form now covers all 104 `user_profiles` columns, and the list
// endpoint carries only the thirteen legacy ones. Widening the LIST to send a
// hundred more columns per row would cost every page load of twenty accounts,
// for data that is opened on one row at a time — so the modal asks the detail
// endpoint (the same one the read-only عرض page uses) for the one row it needs.
//
// Shared by UsersPage and StaffPage, which host the identical modal; the two
// had already drifted once on the field list, and one hook is how they stop.
//
// The hook returns the four states the modal renders: `profile` (content),
// `loading` (skeleton), `error` (friendly message with a way out) and `reload`
// (the Retry the error offers).

import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from './api'

export type UserEditProfile = {
  /** The merged account + profile row, or null while loading / on failure. */
  profile: Record<string, unknown> | null
  loading: boolean
  error: string | null
  reload: () => void
}

/**
 * @param userId the account whose profile to load, or null when the modal is
 *   closed — in which case nothing is fetched and the state is cleared, so
 *   reopening on a different row can never flash the previous person's data.
 */
export function useUserEditProfile(userId: number | null): UserEditProfile {
  // One piece of state holding the outcome of one request, tagged with the
  // request it answered. Everything the hook returns is then derived from it,
  // so the effect below clears nothing: a result for a different user (or a
  // previous reload) simply is not the current one, which is exactly the
  // guarantee the old reset-then-fetch was written to give.
  const [result, setResult] = useState<{
    key: string
    profile: Record<string, unknown> | null
    error: string | null
  } | null>(null)
  const [tick, setTick] = useState(0)

  const reload = useCallback(() => setTick((n) => n + 1), [])

  const requestKey = `${userId}|${tick}`
  const current = result && result.key === requestKey ? result : null
  const profile = current?.profile ?? null
  const error = current?.error ?? null
  // Closed means nothing is being fetched, so it is not loading either.
  const loading = userId !== null && current === null

  useEffect(() => {
    if (userId === null) return
    let cancelled = false
    api
      .get<{ item: Record<string, unknown> }>(`/api/admin/detail/users/${userId}`)
      .then((r) => {
        if (!cancelled) setResult({ key: requestKey, profile: r.data.item, error: null })
      })
      .catch((e) => {
        // Never swallowed: the operator sees a localized message and a Retry,
        // and the technical detail stays in the console for support.
        if (!cancelled) setResult({ key: requestKey, profile: null, error: describeError(e) })
      })
    return () => {
      cancelled = true
    }
  }, [userId, tick, requestKey])

  return { profile, loading, error, reload }
}
