// useHighlightedRow.tsx — small helper for the "land on the list + pulse the
// target row" interaction (Phase 16).
//
// The dashboard's live event feed sends admins to e.g.
//   /donations?highlight=11
// when they click a row. This hook reads that param, scrolls the matching
// <tr> into view, and exposes a boolean for the list page to attach the
// `.is-highlighted` CSS class to the target row.
//
// Pages opt-in with two lines:
//
//   const { highlightedId, isHighlighted, banner } = useHighlightedRow()
//   // …
//   <tr className={isHighlighted(row.id) ? 'is-highlighted' : ''}>
//
// The banner element is a ready-made component the page can drop at the top
// of its layout (or skip if it has its own).

import { useEffect, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useI18n } from './i18n'

// useHighlightedRow — wraps the URL param + scroll plumbing into a single
// hook with a focused API surface.
//
// Phase 18d — the highlight is now STICKY: it remains active as long as the
// URL has `?highlight=<id>`. The initial CSS pulse animation still runs once
// for ~4s to grab attention; after that, the persistent left-border + bg
// tint stays so the admin can scroll away and come back without losing the
// "this is the row I jumped to" marker. The user clears it via the
// HighlightBanner's Dismiss button.
export function useHighlightedRow(opts?: {
  /** Param name to read; defaults to "highlight". */
  param?: string
}) {
  const paramName = opts?.param ?? 'highlight'

  const [params, setParams] = useSearchParams()
  const raw = params.get(paramName) ?? ''
  // Normalised id — strings, never numbers, so comparison is stable across
  // sources (URL is always a string; row.id may be number or string).
  const highlightedId = raw.trim()

  // Active is now directly tied to "is the URL param present?" — no timer.
  // The CSS animation owns its own duration via @keyframes.
  const active = Boolean(highlightedId)

  // Auto-scroll into view once on mount / id change. The row uses
  // `scroll-margin-top` in CSS so it doesn't slide under the topbar.
  useEffect(() => {
    if (!highlightedId) return
    // Defer to next frame so the table has actually rendered the row.
    const raf = requestAnimationFrame(() => {
      const el = document.querySelector(
        `[data-highlight-id="${CSS.escape(highlightedId)}"]`,
      ) as HTMLElement | null
      el?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    })
    return () => cancelAnimationFrame(raf)
  }, [highlightedId])

  // Stable predicate the consumer uses inside a map() to decide which row
  // gets the className. Returns false for non-highlighted rows.
  const isHighlighted = useMemo(
    () => (id: string | number | undefined | null) =>
      active && id != null && String(id) === highlightedId,
    [active, highlightedId],
  )

  // Convenience clear — drops the URL param without leaving a trailing "?".
  function clearHighlight() {
    const next = new URLSearchParams(params)
    next.delete(paramName)
    setParams(next, { replace: true })
  }

  return { highlightedId, active, isHighlighted, clearHighlight }
}

// HighlightBanner — drop this at the top of a list page to confirm where the
// admin landed and offer a quick "dismiss" button. Renders nothing when there
// is no highlighted id, so it's safe to include unconditionally.
//
// `kind` is the noun shown ("Donation #11", "Sponsorship #4"). The default
// "Item" is fine but pages should pass a specific noun for clarity.
export function HighlightBanner({ kind = 'Item' }: { kind?: string }) {
  const { highlightedId, clearHighlight } = useHighlightedRow()
  const { t } = useI18n()
  if (!highlightedId) return null
  return (
    <div className="highlight-banner" role="status">
      <span className="hb-icon" aria-hidden="true">⚡</span>
      <span className="hb-text">
        <strong>{kind} #{highlightedId}</strong>{' '}
        {t('highlight.opened_from_feed')}
      </span>
      <button type="button" onClick={clearHighlight}>{t('highlight.dismiss')}</button>
    </div>
  )
}
