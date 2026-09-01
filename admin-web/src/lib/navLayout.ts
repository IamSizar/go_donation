// navLayout — single source of truth for the sidebar's nav items AND their
// default grouping (Note #29), shared between AppShell.tsx (which renders
// it) and SettingsPage.tsx (which lets a Super-Admin reorder/regroup it).
//
// `NAV` is the per-item metadata (label key, permission gating, pending-
// count key) — this never changes at runtime. `DEFAULT_NAV_SECTIONS` is the
// out-of-the-box arrangement of those items into groups. A Super-Admin can
// override the ARRANGEMENT (order + grouping) via the nav-layout setting,
// but never the per-item metadata — permissions/labels always come from NAV.

import type { PendingCounts } from './pendingCounts'

export type NavItem = {
  to: string
  tKey: string
  countKey?: keyof Omit<PendingCounts, 'total'>
  // adminOnly items only render for admin-level staff (Phase 7 · Trash).
  adminOnly?: boolean
  // superAdminOnly items render only for the Primary Administrator (Section 24).
  superAdminOnly?: boolean
  // module is the permission slug this item maps to; when the effective
  // permissions say the tier can't `view` it, the item is hidden (Section 24).
  module?: string
}

export const NAV: NavItem[] = [
  { to: '/',              tKey: 'nav.dashboard',      module: 'dashboard' },
  { to: '/users',         tKey: 'nav.users',          module: 'users' },
  { to: '/registrations', tKey: 'nav.registrations', countKey: 'registrations', module: 'registrations' },
  { to: '/profile-changes', tKey: 'nav.profile_changes', module: 'users' },
  { to: '/campaigns',     tKey: 'nav.campaigns',      module: 'campaigns' },
  { to: '/donations',     tKey: 'nav.donations',     countKey: 'donations', module: 'donations' },
  { to: '/donation-codes', tKey: 'nav.donation_codes', module: 'donations' },
  { to: '/payment-methods', tKey: 'nav.payment_methods', module: 'donations' },
  // M7 — the donor-facing giving types, managed like payment methods.
  { to: '/donation-types', tKey: 'nav.donation_types', module: 'donations' },
  { to: '/beneficiary',   tKey: 'nav.beneficiary',   countKey: 'beneficiary', module: 'beneficiary' },
  { to: '/project-categories', tKey: 'nav.project_categories', module: 'beneficiary' },
  { to: '/sponsorship-types', tKey: 'nav.sponsorship_types', module: 'sponsorships' },
  { to: '/marketplace',   tKey: 'nav.marketplace',   countKey: 'marketplace', module: 'marketplace' },
  { to: '/marketplace-categories', tKey: 'nav.marketplace_categories', module: 'marketplace' },
  { to: '/marriage',      tKey: 'nav.marriage',      countKey: 'marriage', module: 'marriage' },
  { to: '/marriage-requests', tKey: 'nav.marriage_requests', module: 'marriage' },
  { to: '/marriage-chats', tKey: 'nav.marriage_chats', module: 'marriage' },
  { to: '/marriage-subscriptions', tKey: 'nav.marriage_subscriptions', module: 'marriage' },
  { to: '/partners',      tKey: 'nav.partners',       module: 'partners' },
  { to: '/media',         tKey: 'nav.media',          module: 'media' },
  { to: '/media-categories', tKey: 'nav.media_categories', module: 'media' },
  { to: '/comments',      tKey: 'nav.comments',        module: 'media' },
  { to: '/post-activity', tKey: 'nav.post_activity',   module: 'media' },
  { to: '/banned-words',  tKey: 'nav.banned_words',    module: 'media' },
  { to: '/community',     tKey: 'nav.community',       module: 'community' },
  { to: '/city-guide',    tKey: 'nav.city_guide',     module: 'city' },
  { to: '/city-sectors',  tKey: 'nav.city_sectors',   module: 'city' },
  { to: '/city-categories', tKey: 'nav.city_categories', module: 'community' },
  { to: '/field-rules',   tKey: 'nav.field_rules',    module: 'users' },
  { to: '/receipts',      tKey: 'nav.receipts',       module: 'beneficiary' },
  { to: '/messages',      tKey: 'nav.messages',        module: 'messages' },
  { to: '/staff-chat',    tKey: 'nav.staff_chat' },
  { to: '/volunteers',    tKey: 'nav.volunteers',    countKey: 'volunteers', module: 'volunteers' },
  { to: '/volunteer-board', tKey: 'nav.volunteer_board', module: 'volunteers' },
  { to: '/tasks',          tKey: 'nav.tasks',            module: 'tasks' },
  { to: '/case-volunteer-chats', tKey: 'nav.case_volunteer_chats', module: 'volunteers' },
  { to: '/missions',      tKey: 'nav.missions',        module: 'missions' },
  { to: '/sponsorships',  tKey: 'nav.sponsorships',  countKey: 'sponsorships', module: 'sponsorships' },
  { to: '/in-kind',       tKey: 'nav.in_kind',       countKey: 'in_kind', module: 'in_kind' },
  { to: '/support',       tKey: 'nav.support',       countKey: 'support', module: 'support' },
  { to: '/notifications', tKey: 'nav.notifications',  module: 'notifications' },
  { to: '/push',          tKey: 'nav.push',           module: 'push' },
  { to: '/reports',       tKey: 'nav.reports',        module: 'reports' },
  { to: '/audit-logs',    tKey: 'nav.audit_logs',     module: 'audit' },
  { to: '/trash',         tKey: 'nav.trash', adminOnly: true, module: 'trash' },
  { to: '/staff',         tKey: 'nav.staff',       superAdminOnly: true },
  { to: '/permissions',   tKey: 'nav.permissions', superAdminOnly: true },
  { to: '/guest-access',  tKey: 'nav.guest_access', superAdminOnly: true },
  { to: '/terms',         tKey: 'nav.terms',        superAdminOnly: true },
  { to: '/about',         tKey: 'nav.about',        superAdminOnly: true },
  { to: '/marriage-about', tKey: 'nav.marriageAbout', module: 'settings' },
  { to: '/marriage-contact', tKey: 'nav.marriageContact', module: 'settings' },
  { to: '/city-guide-about', tKey: 'nav.cityGuideAbout', module: 'settings' },
  { to: '/city-guide-contact', tKey: 'nav.cityGuideContact', module: 'settings' },
  { to: '/humanitarian-work', tKey: 'nav.humanitarian_work', superAdminOnly: true },
  { to: '/contact',       tKey: 'nav.contact',      superAdminOnly: true },
  { to: '/settings',      tKey: 'nav.settings',     superAdminOnly: true },
]

export const navByTo = new Map(NAV.map((n) => [n.to, n]))

/** True when `path` is a nav item's own route, or a route nested under it.
 *
 * Deliberately NOT a bare `startsWith`. Sibling routes share prefixes —
 * '/marriage' vs '/marriage-requests', '/marketplace' vs
 * '/marketplace-categories', '/media' vs '/media-categories' — so a prefix
 * test lights up the parent AND the child at the same time. That is both
 * visibly wrong and the cause of the flickering highlight: the active pill is
 * a framer-motion `layoutId`, and two elements claiming the same layoutId
 * make it jump between them instead of sliding once. */
export function isNavPathActive(path: string, to: string): boolean {
  if (to === '/') return path === '/'
  return path === to || path.startsWith(to + '/')
}

export type NavSection =
  | { kind: 'item'; to: string }
  | { kind: 'group'; key: string; tKey: string; items: string[] }

// ─── Access & Staff — the one group that is not freely arrangeable ────────
//
// The owner's ask: "everything to do with managing staff and admins and
// anyone who has access in the app — put them all in the settings section."
// The test they set is a question: "who can get into this system, and what
// can they do?" Every answer must be findable in ONE place.
//
// These pages live INSIDE the System Settings group, at the TOP of it.
//
// An earlier pass gave them their own titled group sitting directly above
// System Settings, reasoning that dropping them INTO a grab-bag of ~15
// content and payment pages (Terms, About, payment methods, Trash) would
// scatter them. The owner has since been explicit — "move this section all
// of it inside the system settings" — so that is what this does. The
// scattering concern is answered by ORDER instead of by a heading: the
// access pages are pinned to the front of the group, ahead of the content
// pages, so they are the first thing under it rather than mixed through it.
//
// `/audit-logs` is included deliberately. It is not access CONTROL — it is
// the record of what staff DID — so it could equally have stayed under
// Monitoring & Reports. It is here because it answers the second half of the
// owner's question ("...and what can they do?") with evidence rather than
// policy, and because someone auditing a staff member should not have to
// know which of two sections the dashboard filed it under. Note it is NOT
// superAdminOnly (it is gated by the `audit` module) and moving it does not
// change that — grouping is presentation, gating lives in NAV.
//
// ACCESS_GROUP_KEY is KEPT even though no default layout creates that group
// any more: a Super Admin who saved a layout while it existed still has it
// stored, and reconcileNavSections needs the key to find those items and
// fold them into System Settings.
export const ACCESS_GROUP_KEY = 'access_control'

/** The routes that must always live together in the Access & Staff group,
 *  in the order they should appear. Order = policy first (who exists, what
 *  their tier may do, how guests get in), then the record, then the
 *  dashboard's own settings page. */
export const ACCESS_ITEMS: string[] = [
  '/staff', '/permissions', '/guest-access', '/audit-logs', '/settings',
]

// The group titles a Super-Admin can regroup items under. `tKey` here is
// only used for GROUPS a section actually references — a custom layout that
// invents a brand new group key would have no label, so the settings editor
// only ever assigns items to one of these known keys (never a free-typed one).
export const GROUP_DEFS: { key: string; tKey: string }[] = [
  { key: 'users_members', tKey: 'nav_group.users_members' },
  { key: 'aid_campaigns', tKey: 'nav_group.aid_campaigns' },
  { key: 'city_guide', tKey: 'nav_group.city_guide' },
  { key: 'store_marketplace', tKey: 'nav_group.store_marketplace' },
  { key: 'marriage', tKey: 'nav_group.marriage' },
  { key: 'comments_activities', tKey: 'nav_group.comments_activities' },
  { key: 'communication_support', tKey: 'nav_group.communication_support' },
  { key: 'monitoring_reports', tKey: 'nav_group.monitoring_reports' },
  { key: ACCESS_GROUP_KEY, tKey: 'nav_group.access_control' },
  { key: 'system_settings', tKey: 'nav_group.system_settings' },
]
const groupTKeyByKey = new Map(GROUP_DEFS.map((g) => [g.key, g.tKey]))

export const DEFAULT_NAV_SECTIONS: NavSection[] = [
  { kind: 'item', to: '/' },
  {
    kind: 'group', key: 'users_members', tKey: 'nav_group.users_members',
    items: ['/users', '/beneficiary', '/volunteers', '/volunteer-board', '/tasks',
            '/case-volunteer-chats', '/partners'],
  },
  {
    kind: 'group', key: 'aid_campaigns', tKey: 'nav_group.aid_campaigns',
    items: ['/campaigns', '/donations', '/in-kind', '/receipts', '/project-categories', '/sponsorships', '/sponsorship-types'],
  },
  {
    kind: 'group', key: 'city_guide', tKey: 'nav_group.city_guide',
    items: ['/city-guide', '/city-sectors', '/city-categories', '/community'],
  },
  {
    kind: 'group', key: 'store_marketplace', tKey: 'nav_group.store_marketplace',
    items: ['/marketplace', '/marketplace-categories'],
  },
  {
    kind: 'group', key: 'marriage', tKey: 'nav_group.marriage',
    items: ['/marriage', '/marriage-requests', '/marriage-chats', '/marriage-subscriptions'],
  },
  {
    kind: 'group', key: 'comments_activities', tKey: 'nav_group.comments_activities',
    items: ['/comments', '/post-activity', '/banned-words'],
  },
  {
    kind: 'group', key: 'communication_support', tKey: 'nav_group.communication_support',
    items: ['/messages', '/staff-chat', '/notifications', '/push', '/support', '/contact'],
  },
  {
    kind: 'group', key: 'monitoring_reports', tKey: 'nav_group.monitoring_reports',
    items: ['/registrations', '/profile-changes', '/missions', '/reports', '/media', '/media-categories'],
  },
  {
    kind: 'group', key: 'system_settings', tKey: 'nav_group.system_settings',
    items: [
      // Access & staff first — see ACCESS_ITEMS above.
      ...ACCESS_ITEMS,
      '/payment-methods', '/donation-types', '/donation-codes', '/field-rules',
      '/terms', '/about', '/humanitarian-work',
      '/marriage-about', '/marriage-contact', '/city-guide-about', '/city-guide-contact',
      '/trash',
    ],
  },
]

// reconcileNavSections is the ONE place that turns "whatever's saved in the
// nav-layout setting" into something safe to render/edit. It:
//   1. Drops any `to`/group-key referencing a route that no longer exists
//      (a saved layout can go stale after a code change removes a page).
//   2. Appends any CURRENT nav item missing from the saved layout — e.g. a
//      page added after the admin last customized their sidebar — into a
//      trailing group, so a stale layout can only ever reorder pages, never
//      silently hide one.
//   3. Falls back to DEFAULT_NAV_SECTIONS entirely when given null/invalid
//      input (nobody has customized yet, or the stored value is corrupt).
//   4. Gathers the Access & Staff pages into their own group wherever they
//      were left — see consolidateAccessGroup for WHY that is not optional.
export function reconcileNavSections(custom: NavSection[] | null | undefined): NavSection[] {
  if (!custom || !Array.isArray(custom) || custom.length === 0) return DEFAULT_NAV_SECTIONS

  const seen = new Set<string>()
  const sections: NavSection[] = []
  for (const raw of custom) {
    if (!raw || typeof raw !== 'object') continue
    if (raw.kind === 'item') {
      if (!navByTo.has(raw.to) || seen.has(raw.to)) continue
      seen.add(raw.to)
      sections.push({ kind: 'item', to: raw.to })
    } else if (raw.kind === 'group') {
      const items = (raw.items ?? []).filter((to) => navByTo.has(to) && !seen.has(to))
      if (items.length === 0) continue
      // Regenerate the label from the known group defs (not whatever tKey
      // was saved) so a hand-edited/stale value can't inject an unknown
      // translation key that renders as a raw key string.
      const tKey = groupTKeyByKey.get(raw.key) ?? raw.tKey
      // `seen` is marked only once the section is definitely being kept.
      // Marking it earlier lost pages: a group with an unknown key is dropped
      // here, and its items — already marked seen — then failed the "missing"
      // sweep below and disappeared from the sidebar entirely.
      if (!tKey) continue
      items.forEach((to) => seen.add(to))
      sections.push({ kind: 'group', key: raw.key, tKey, items })
    }
  }

  const missing = NAV.map((n) => n.to).filter((to) => !seen.has(to))
  if (missing.length > 0) {
    sections.push({ kind: 'group', key: '__unsorted', tKey: 'nav_group.unsorted', items: missing })
  }
  // Runs LAST, deliberately: after the unsorted catch-all, so an access page
  // the saved layout never mentioned is pulled out of __unsorted and into the
  // Access & Staff group rather than being left in the trailing bucket.
  const gathered = consolidateAccessGroup(sections)
  return gathered.length > 0 ? gathered : DEFAULT_NAV_SECTIONS
}

/**
 * Gathers ACCESS_ITEMS to the TOP of the System Settings group, in place.
 *
 * WHY THIS EXISTS — the thing that would otherwise make this whole change a
 * no-op for the one person who asked for it. The sidebar arrangement is saved
 * per Super-Admin, and a saved arrangement wins: reconcile keeps it and only
 * APPENDS pages it does not mention. So editing DEFAULT_NAV_SECTIONS moves
 * these pages for a fresh admin and moves them for nobody who has ever
 * touched the layout editor — very likely including the owner. Their Guest
 * Access would have stayed exactly where it was.
 *
 * The alternative was to tell the owner to press "Reset layout", which throws
 * away every other customization they made. So the gathering is applied on
 * top of the saved layout instead, and it is surgical:
 *   - ONLY the five ACCESS_ITEMS are relocated. Every other item keeps its
 *     saved group and its saved order; every other group keeps its position.
 *   - Nothing is dropped. Items are moved, never removed, so the "no page can
 *     vanish from the sidebar" guarantee above still holds.
 *   - Any NON-access item an admin had filed under the old Access & Staff
 *     group is kept — it moves into System Settings with them rather than
 *     being lost when that group disappears.
 *   - They land at the FRONT of System Settings, ahead of the content and
 *     payment pages, so "who can get in and what can they do" is the first
 *     thing under the heading rather than mixed through fifteen others.
 *   - It is idempotent: running it on its own output changes nothing.
 *
 * KNOWN FAILURE MODE, accepted: a Super-Admin who deliberately filed, say,
 * Audit Logs under Monitoring & Reports cannot keep it there any more — this
 * gathering overrides that one preference by design, because the owner asked
 * for exactly that. To stop the UI from lying about it, SidebarLayoutEditor
 * renders these five without a "move to" dropdown and says they are pinned;
 * otherwise an admin could move one, save, and watch it snap back on reload.
 */
function consolidateAccessGroup(sections: NavSection[]): NavSection[] {
  const access = new Set(ACCESS_ITEMS.filter((to) => navByTo.has(to)))
  if (access.size === 0) return sections

  // Where the group should land. Preference order, most predictable first:
  // immediately above System Settings (matching DEFAULT_NAV_SECTIONS, so every
  // admin ends up with the same Settings area), else where the layout already
  // kept its first access page, else the end. -1 until one of those is found.
  let insertAt = -1
  // Non-access items an admin filed under Access & Staff themselves — kept.
  const extras: string[] = []
  const stripped: NavSection[] = []

  for (const section of sections) {
    if (section.kind === 'item') {
      if (access.has(section.to)) {
        if (insertAt < 0) insertAt = stripped.length
        continue
      }
      stripped.push(section)
      continue
    }
    const kept = section.items.filter((to) => !access.has(to))
    if (section.key === ACCESS_GROUP_KEY) {
      extras.push(...kept)
      if (insertAt < 0) insertAt = stripped.length
      continue
    }
    if (kept.length !== section.items.length && insertAt < 0) insertAt = stripped.length
    // A group left with nothing but access pages disappears rather than
    // rendering an empty heading.
    if (kept.length > 0) stripped.push({ ...section, items: kept })
  }

  // The access pages go to the FRONT of System Settings. `extras` — anything
  // non-access the admin had filed under the old Access & Staff group — rides
  // along behind them rather than being dropped with that group.
  const pinned = [...ACCESS_ITEMS.filter((to) => navByTo.has(to)), ...extras]

  const sys = stripped.findIndex((x) => x.kind === 'group' && x.key === 'system_settings')
  if (sys >= 0) {
    const group = stripped[sys] as Extract<NavSection, { kind: 'group' }>
    // Filter first so re-running this cannot duplicate an entry: the pinned
    // list is re-prepended every time, so any copy already inside must go.
    const rest = group.items.filter((to) => !pinned.includes(to))
    stripped[sys] = { ...group, items: [...pinned, ...rest] }
    return stripped
  }

  // No System Settings group in this saved layout (an admin renamed or
  // emptied it). Recreate it rather than dropping the pages on the floor,
  // where the admin's own layout already had the first of them.
  if (insertAt < 0) insertAt = stripped.length
  const group: NavSection = {
    kind: 'group',
    key: 'system_settings',
    tKey: 'nav_group.system_settings',
    items: pinned,
  }
  stripped.splice(Math.min(insertAt, stripped.length), 0, group)
  return stripped
}
