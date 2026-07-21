// AvailabilityCell — Note #20. The Volunteers table's Availability column
// used to render a volunteer's full weekly schedule as a vertical stack of
// day+time rows directly in the cell — fine for 1-2 days, but for someone
// available most of the week it made the row tall and the table cluttered
// (the client's exact complaint: "long and distracting fields... displaying
// all days and hours vertically inside the table").
//
// Now the cell shows a compact "N days" badge; clicking it opens a small
// card with the full breakdown. The card is rendered through a portal with
// position:fixed, positioned against the trigger's real screen coordinates —
// same technique as ActionsMenu (Note #12/#16) — so it's never clipped by
// the table's own overflow:auto scroll wrapper and flips upward near the
// bottom of the table instead of overlapping the row below.
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from 'react'
import { createPortal } from 'react-dom'
import { useI18n } from '../lib/i18n'
import { dayLabelFor } from '../lib/skillCatalogue'
import type { VolunteerScheduleRow } from '../lib/api-types'

type Props = {
  schedule: VolunteerScheduleRow[]
  freeText: string | null
  locale: string | undefined
}

export default function AvailabilityCell({ schedule, freeText, locale }: Props) {
  const { t } = useI18n()
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)
  const btnRef = useRef<HTMLButtonElement>(null)
  const cardRef = useRef<HTMLDivElement>(null)
  const [cardStyle, setCardStyle] = useState<CSSProperties>({ position: 'fixed', top: 0, left: 0, visibility: 'hidden' })

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      const target = e.target as Node
      if (wrapRef.current?.contains(target)) return
      if (cardRef.current?.contains(target)) return
      setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    return () => document.removeEventListener('mousedown', onDocClick)
  }, [])

  useLayoutEffect(() => {
    if (!open) return
    function place() {
      const btn = btnRef.current
      const card = cardRef.current
      if (!btn || !card) return
      const btnRect = btn.getBoundingClientRect()
      const cardRect = card.getBoundingClientRect()
      const margin = 4
      const rtl = document.documentElement.dir === 'rtl'
      let left = rtl ? btnRect.left : btnRect.right - cardRect.width
      left = Math.max(margin, Math.min(left, window.innerWidth - cardRect.width - margin))
      const spaceBelow = window.innerHeight - btnRect.bottom
      const openUp = spaceBelow < cardRect.height + margin && btnRect.top > cardRect.height + margin
      const top = openUp ? btnRect.top - cardRect.height - margin : btnRect.bottom + margin
      setCardStyle({ position: 'fixed', top, left, visibility: 'visible' })
    }
    place()
    window.addEventListener('resize', place)
    window.addEventListener('scroll', place, true)
    return () => {
      window.removeEventListener('resize', place)
      window.removeEventListener('scroll', place, true)
    }
  }, [open, schedule.length])

  if (schedule.length === 0) {
    if (!freeText) return <span className="muted">—</span>
    // Free text is admin/volunteer-typed and can run long — truncate with a
    // hover tooltip rather than let it wrap the row tall (same complaint as
    // the structured case, different cause).
    return (
      <span
        className="muted"
        title={freeText}
        style={{
          display: 'inline-block', maxWidth: '160px', overflow: 'hidden',
          textOverflow: 'ellipsis', whiteSpace: 'nowrap', verticalAlign: 'bottom',
        }}
      >
        {freeText}
      </span>
    )
  }

  return (
    <div ref={wrapRef} style={{ display: 'inline-block' }}>
      <button
        ref={btnRef}
        type="button"
        className="row-edit-btn"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="dialog"
        aria-expanded={open}
      >
        {t('page.volunteers.days_count', { n: schedule.length })} <span aria-hidden="true">▾</span>
      </button>
      {open && createPortal(
        <div ref={cardRef} className="dropdown-menu" role="dialog" style={{ ...cardStyle, padding: '10px 12px' }}>
          <div className="cell-stack" style={{ gap: 6 }}>
            {schedule.map((r) => (
              <div key={r.day} style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: 12 }}>
                <span
                  style={{
                    display: 'inline-block', width: 34, padding: '2px 0', textAlign: 'center',
                    borderRadius: 6, fontWeight: 700, fontSize: 10.5, color: '#fff',
                    background: 'var(--accent, #4F46E5)',
                  }}
                >
                  {dayLabelFor(r.day, locale).slice(0, 3)}
                </span>
                <span style={{ fontFamily: 'monospace' }}>{r.from} – {r.to}</span>
              </div>
            ))}
          </div>
        </div>,
        document.body,
      )}
    </div>
  )
}
