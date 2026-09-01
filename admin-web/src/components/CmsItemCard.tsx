// CmsItemCard — one row of a CMS list (categories, sectors, sponsorship
// types), collapsed until it is being edited.
//
// THE PROBLEM, MEASURED ON THE LIVE DASHBOARD
// Five pages share this shape, and each rendered EVERY item fully expanded:
// four language inputs, an active checkbox, save and delete. With the real
// number of rows that produced
//
//     /city-categories        14,608px   (~21 screens)
//     /media-categories       12,923px
//     /marketplace-categories 11,084px
//
// — pages an operator scrolls for a minute to reach the item they wanted, on
// which every row looks exactly like every other row. The editing surface for
// ONE item was being paid for by all of them.
//
// Collapsed, the same page is a list of names: roughly 50px per item instead
// of ~460px, so /city-categories becomes about one screen and the item you
// want is findable by reading rather than by scrolling.
//
// ─── WHY <details> AND NOT REACT STATE ──────────────────────────────────────
// Keyboard operation, the expanded/collapsed state being announced to a
// screen reader, and Ctrl-F finding text inside a closed card in browsers that
// support it — all of that comes free and none of it would be got right by
// hand on five pages. It also means no page needs a new state hook, which
// keeps the diff on each of them to the two lines that wrap the body.
//
// The reorder buttons stay OUTSIDE the <summary>: they are the one control
// used while the card is closed (reordering is done by reading the list, not
// by opening items), and nesting a button inside a summary makes its click
// fight the disclosure toggle.
import type { ReactNode } from 'react'

export default function CmsItemCard({
  title,
  actions,
  children,
  defaultOpen = false,
}: {
  /** The item's display name — the only thing visible when collapsed. */
  title: ReactNode
  /** Reorder controls; rendered beside the title and usable while closed. */
  actions?: ReactNode
  /** The edit form. Rendered only when the card is open. */
  children: ReactNode
  /** Opened on mount. Used for a freshly added item, which exists to be filled in. */
  defaultOpen?: boolean
}) {
  return (
    <details className="card cms-item" open={defaultOpen}>
      <summary className="cms-item-head">
        <span className="cms-item-title">{title}</span>
      </summary>
      {actions && <div className="cms-item-actions">{actions}</div>}
      <div className="cms-item-body">{children}</div>
    </details>
  )
}
