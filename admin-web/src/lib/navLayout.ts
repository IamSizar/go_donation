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
  { to: '/campaigns',     tKey: 'nav.campaigns',      module: 'campaigns' },
  { to: '/donations',     tKey: 'nav.donations',     countKey: 'donations', module: 'donations' },
  { to: '/donation-codes', tKey: 'nav.donation_codes', module: 'donations' },
  { to: '/payment-methods', tKey: 'nav.payment_methods', module: 'donations' },
  { to: '/beneficiary',   tKey: 'nav.beneficiary',   countKey: 'beneficiary', module: 'beneficiary' },
  { to: '/project-categories', tKey: 'nav.project_categories', module: 'beneficiary' },
  { to: '/marketplace',   tKey: 'nav.marketplace',   countKey: 'marketplace', module: 'marketplace' },
  { to: '/marketplace-categories', tKey: 'nav.marketplace_categories', module: 'marketplace' },
  { to: '/marriage',      tKey: 'nav.marriage',      countKey: 'marriage', module: 'marriage' },
  { to: '/marriage-requests', tKey: 'nav.marriage_requests', module: 'marriage' },
  { to: '/marriage-chats', tKey: 'nav.marriage_chats', module: 'marriage' },
  { to: '/marriage-posts', tKey: 'nav.marriage_posts', module: 'marriage' },
  { to: '/partners',      tKey: 'nav.partners',       module: 'partners' },
  { to: '/media',         tKey: 'nav.media',          module: 'media' },
  { to: '/media-categories', tKey: 'nav.media_categories', module: 'media' },
  { to: '/comments',      tKey: 'nav.comments',        module: 'media' },
  { to: '/banned-words',  tKey: 'nav.banned_words',    module: 'media' },
  { to: '/community',     tKey: 'nav.community',       module: 'community' },
  { to: '/city-guide',    tKey: 'nav.city_guide',     module: 'city' },
  { to: '/city-sectors',  tKey: 'nav.city_sectors',   module: 'city' },
  { to: '/field-rules',   tKey: 'nav.field_rules',    module: 'users' },
  { to: '/receipts',      tKey: 'nav.receipts',       module: 'beneficiary' },
  { to: '/messages',      tKey: 'nav.messages',        module: 'messages' },
  { to: '/staff-chat',    tKey: 'nav.staff_chat' },
  { to: '/volunteers',    tKey: 'nav.volunteers',    countKey: 'volunteers', module: 'volunteers' },
  { to: '/volunteer-board', tKey: 'nav.volunteer_board', module: 'volunteers' },
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
  { to: '/permissions',   tKey: 'nav.permissions', superAdminOnly: true },
  { to: '/guest-access',  tKey: 'nav.guest_access', superAdminOnly: true },
  { to: '/terms',         tKey: 'nav.terms',        superAdminOnly: true },
  { to: '/about',         tKey: 'nav.about',        superAdminOnly: true },
  { to: '/contact',       tKey: 'nav.contact',      superAdminOnly: true },
  { to: '/settings',      tKey: 'nav.settings',     superAdminOnly: true },
]

export const navByTo = new Map(NAV.map((n) => [n.to, n]))

export type NavSection =
  | { kind: 'item'; to: string }
  | { kind: 'group'; key: string; tKey: string; items: string[] }

// The 9 group titles a Super-Admin can regroup items under. `tKey` here is
// only used for GROUPS a section actually references — a custom layout that
// invents a brand new group key would have no label, so the settings editor
// only ever assigns items to one of these known keys (never a free-typed one).
export const GROUP_DEFS: { key: string; tKey: string }[] = [
  { key: 'users_members', tKey: 'nav_group.users_members' },
  { key: 'aid_campaigns', tKey: 'nav_group.aid_campaigns' },
  { key: 'city_guide', tKey: 'nav_group.city_guide' },
  { key: 'store_marketplace', tKey: 'nav_group.store_marketplace' },
  { key: 'communication_support', tKey: 'nav_group.communication_support' },
  { key: 'monitoring_reports', tKey: 'nav_group.monitoring_reports' },
  { key: 'system_settings', tKey: 'nav_group.system_settings' },
]
const groupTKeyByKey = new Map(GROUP_DEFS.map((g) => [g.key, g.tKey]))

export const DEFAULT_NAV_SECTIONS: NavSection[] = [
  { kind: 'item', to: '/' },
  {
    kind: 'group', key: 'users_members', tKey: 'nav_group.users_members',
    items: ['/users', '/beneficiary', '/volunteers', '/volunteer-board', '/case-volunteer-chats', '/guest-access'],
  },
  {
    kind: 'group', key: 'aid_campaigns', tKey: 'nav_group.aid_campaigns',
    items: ['/campaigns', '/donations', '/in-kind', '/receipts', '/project-categories', '/sponsorships'],
  },
  {
    kind: 'group', key: 'city_guide', tKey: 'nav_group.city_guide',
    items: ['/city-guide', '/city-sectors', '/community'],
  },
  {
    kind: 'group', key: 'store_marketplace', tKey: 'nav_group.store_marketplace',
    items: ['/marketplace', '/marketplace-categories', '/comments'],
  },
  { kind: 'item', to: '/marriage' },
  { kind: 'item', to: '/marriage-requests' },
  { kind: 'item', to: '/marriage-chats' },
  { kind: 'item', to: '/marriage-posts' },
  { kind: 'item', to: '/partners' },
  {
    kind: 'group', key: 'communication_support', tKey: 'nav_group.communication_support',
    items: ['/messages', '/staff-chat', '/notifications', '/push', '/support', '/contact'],
  },
  {
    kind: 'group', key: 'monitoring_reports', tKey: 'nav_group.monitoring_reports',
    items: ['/registrations', '/missions', '/reports', '/audit-logs'],
  },
  {
    kind: 'group', key: 'system_settings', tKey: 'nav_group.system_settings',
    items: [
      '/payment-methods', '/donation-codes', '/field-rules', '/banned-words',
      '/permissions', '/terms', '/about', '/media', '/media-categories',
      '/trash', '/settings',
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
      items.forEach((to) => seen.add(to))
      if (items.length === 0) continue
      // Regenerate the label from the known group defs (not whatever tKey
      // was saved) so a hand-edited/stale value can't inject an unknown
      // translation key that renders as a raw key string.
      const tKey = groupTKeyByKey.get(raw.key) ?? raw.tKey
      if (!tKey) continue
      sections.push({ kind: 'group', key: raw.key, tKey, items })
    }
  }

  const missing = NAV.map((n) => n.to).filter((to) => !seen.has(to))
  if (missing.length > 0) {
    sections.push({ kind: 'group', key: '__unsorted', tKey: 'nav_group.unsorted', items: missing })
  }
  return sections.length > 0 ? sections : DEFAULT_NAV_SECTIONS
}
