// DateCell — client item C3. Every dashboard table prints a timestamp the
// same way: the DATE on top, the TIME underneath, so the column stays narrow
// and two rows can be compared down the page instead of read across it.
//
// WHY A COMPONENT AND NOT JUST A HELPER
// lib/dates.ts already had formatDateParts(), but the markup around it — a
// .cell-stack wrapper plus a smaller second line — was copy-pasted into nine
// pages, and the copies had already drifted apart: some rendered the date
// muted and some not, some printed an em dash for a missing value and some
// left the cell blank. The client's complaint is about consistency, so the
// markup lives in one place now and the pages import it.
//
// WHY <time> RATHER THAN <div>
// The stack carries the machine-readable value in `datetime` alongside the
// human-readable one, which the two list rows that used <time> before this
// component (ChatGroupsPage, ConnectRequestsPage) already relied on and the
// table cells were silently dropping. <time> is phrasing content and the
// two lines are spans, so the markup stays valid; .cell-stack does the
// column layout through CSS, not through the element name.
//
// NOT FOR TRUE DATE COLUMNS. media_posts.event_date and
// sponsorships.next_due_date have no time component — see the note on
// formatDateOnly in lib/dates.ts. Stacking those would print a meaningless
// 00:00, so they keep formatDateOnly.
import type { CSSProperties } from 'react'
import { formatDateParts } from '../lib/dates'

/** Props for {@link DateCell}. */
type Props = {
  /** The ISO timestamp to show. Null, undefined and '' render the em dash. */
  value: string | null | undefined
  /** Extra classes on the stack, appended to `cell-stack`. */
  className?: string
  /** Inline style on the stack, e.g. a table cell's alignment. */
  style?: CSSProperties
}

/**
 * A timestamp as two lines: the date, and the time under it in slightly
 * smaller type.
 *
 * @param value      the ISO timestamp; a missing one renders `—` (the em dash
 *                   every other empty cell in the dashboard uses) and a value
 *                   the browser cannot parse renders verbatim, never
 *                   "Invalid Date".
 * @param className  extra classes for the stack element.
 * @param style      inline style for the stack element.
 * @returns          the stacked cell, or the placeholder for an empty value.
 */
export default function DateCell({ value, className, style }: Props) {
  const { date, time } = formatDateParts(value)

  // No timestamp at all: the dashboard's placeholder, so the column reads as
  // "nothing here" rather than as a rendering failure.
  if (!date) return <span className="muted" style={style}>—</span>

  // An unparseable value has a date part (the raw string, per formatDateParts)
  // but no time. It gets no <time> wrapper: `datetime` must be a valid HTML
  // date string, and a string the browser could not parse is not one.
  if (!time) return <span className="muted" style={style}>{date}</span>

  return (
    <time className={className ? `cell-stack ${className}` : 'cell-stack'} dateTime={value ?? undefined} style={style}>
      <span className="muted">{date}</span>
      <span className="muted" style={{ fontSize: '0.85em' }}>{time}</span>
    </time>
  )
}
