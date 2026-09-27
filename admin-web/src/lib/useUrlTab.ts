import { useSearchParams } from 'react-router-dom'

/**
 * A page's in-page tab, kept in the URL (`?tab=…`) instead of component state.
 *
 * The top bar's تحديث re-mounts the routed page (see AppShell), which resets
 * any useState — a page holding its tab there would jump back to its first
 * tab on every refresh, when the operator asked to refresh the tab they are
 * on. The URL survives the re-mount (and Back/Next, and a shared link).
 *
 * `replace` so switching tabs doesn't pile entries onto the history that the
 * bar's رجوع would then have to walk back through one tab at a time. Other
 * query params (e.g. a row highlight) are left untouched.
 */
export function useUrlTab<T extends string>(tabs: readonly T[], fallback: T): [T, (next: T) => void] {
  const [params, setParams] = useSearchParams()
  const raw = params.get('tab')
  const tab = raw !== null && (tabs as readonly string[]).includes(raw) ? (raw as T) : fallback
  const setTab = (next: T) =>
    setParams(
      (prev) => {
        const p = new URLSearchParams(prev)
        p.set('tab', next)
        return p
      },
      { replace: true },
    )
  return [tab, setTab]
}
