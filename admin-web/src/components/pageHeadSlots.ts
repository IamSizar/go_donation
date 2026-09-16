// pageHeadSlots.ts — the three portal targets the top action bar exposes.
//
// Split out of PageHead.tsx because a file that exports a component may not
// also export React contexts: fast refresh recreates a module's bindings on
// every edit, so a context declared beside a component would be swapped for a
// brand-new one and every Provider/consumer pair would come apart mid-session
// (react-refresh/only-export-components).
//
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

import { createContext } from 'react'

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
