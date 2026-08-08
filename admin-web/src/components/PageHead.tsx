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

export default function PageHead({ children }: { children: ReactNode }) {
  const slot = useContext(PageHeadSlotContext)
  const head = <div className="page-head">{children}</div>
  // The slot is captured by a ref callback in AppShell, so it is null for
  // exactly one render on first mount. Rendering in place until then keeps
  // the header present rather than blank; every later route change already
  // has the slot and portals straight away.
  return slot ? createPortal(head, slot) : head
}
