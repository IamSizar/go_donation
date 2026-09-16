import { useContext, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import {
  BarSecondarySlotContext,
  PageActionsSlotContext,
  PageHeadSlotContext,
} from './pageHeadSlots'

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
