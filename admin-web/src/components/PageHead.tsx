import { createContext, useContext, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

// Every section used to render two stacked header strips: the shared
// TopActionBar (Back / Next / Refresh … Save) and, below it, the page's own
// `.page-head` (title + subtitle on the left, search / "New …" / Export on
// the right). They live in different parts of the tree — TopActionBar is a
// sibling of <Outlet/> in AppShell, the page head is two levels deeper inside
// the route's motion wrapper — so no amount of CSS can pull them onto one
// line.
//
// Instead the page head renders into a slot INSIDE the action bar via a
// portal: the title lands next to Back/Next, and the page's action row lands
// next to Save. Pages keep authoring the exact same JSX they always did;
// only the wrapper element changed from <div className="page-head"> to
// <PageHead>.
export const PageHeadSlotContext = createContext<HTMLElement | null>(null)

// Two more slots in the same bar, for pages whose header needs more than the
// middle strip can hold:
//   PageActions   — sits immediately LEFT of Save, for the page's primary
//                   action ("+ Add place"), so the two main buttons are
//                   together instead of the action being buried among filters.
//   BarSecondary  — a full-width line that wraps BELOW the buttons, starting
//                   under Back. For overflow filters that would otherwise
//                   squeeze the first line.
export const PageActionsSlotContext = createContext<HTMLElement | null>(null)
export const BarSecondarySlotContext = createContext<HTMLElement | null>(null)

export default function PageHead({ children }: { children: ReactNode }) {
  const slot = useContext(PageHeadSlotContext)
  const head = <div className="page-head">{children}</div>
  // The slot is captured by a ref callback in AppShell, so it is null for
  // exactly one render on first mount. Rendering in place until then keeps
  // the header present rather than blank; every later route change already
  // has the slot and portals straight away.
  return slot ? createPortal(head, slot) : head
}

export function PageActions({ children }: { children: ReactNode }) {
  const slot = useContext(PageActionsSlotContext)
  // No fallback render here: unlike the head, these are loose buttons with no
  // wrapper of their own, so dropping them in place for one frame would put
  // them in the middle of the page body. Waiting one render is invisible.
  return slot ? createPortal(<>{children}</>, slot) : null
}

export function BarSecondary({ children }: { children: ReactNode }) {
  const slot = useContext(BarSecondarySlotContext)
  return slot ? createPortal(<div className="row">{children}</div>, slot) : null
}
