// test-nav-layout.mjs — behavioural tests for src/lib/navLayout.ts.
//
// WHY THIS EXISTS
// The sidebar arrangement is data, and it is data that can be OVERRIDDEN and
// SAVED per Super-Admin. That makes two silent failures possible, and both of
// them are the kind you only notice in production:
//
//   1. A page stops appearing in the sidebar at all. reconcileNavSections has
//      a guard for this (it appends anything the saved layout does not
//      mention into a trailing "unsorted" group) and the guard is only as good
//      as the test that pins it — so the first test here walks every entry in
//      NAV and demands it appear somewhere in the reconciled output, for the
//      default layout AND for a deliberately incomplete saved one.
//
//   2. A page becomes reachable by someone who should not reach it. Grouping
//      is presentation; gating lives on the NAV item. Moving items between
//      groups must therefore leave `superAdminOnly` untouched, and the test
//      below asserts the exact set rather than trusting a read-through.
//
// The rest pins the Access & Staff gathering: that the five access pages land
// together in the default layout, and — the point of the whole change — that
// they ALSO land together for an admin whose saved layout predates it, while
// every other thing that admin arranged survives.
//
// Zero dependencies, like the other scripts here:   npm run test:nav
// Arrange → Act → Assert throughout; each case names the behaviour it pins.
import assert from 'node:assert/strict'
import test from 'node:test'
import {
  NAV, DEFAULT_NAV_SECTIONS, ACCESS_GROUP_KEY, ACCESS_ITEMS, reconcileNavSections,
} from '../src/lib/navLayout.ts'

// ─── Helpers ─────────────────────────────────────────────────────────────

/** Every route the reconciled sections put in front of the admin. */
const routesIn = (sections) =>
  sections.flatMap((s) => (s.kind === 'item' ? [s.to] : s.items))

/** The section an item ended up in, or undefined. */
const sectionOf = (sections, to) =>
  sections.find((s) => (s.kind === 'item' ? s.to === to : s.items.includes(to)))

const groupNamed = (sections, key) =>
  sections.find((s) => s.kind === 'group' && s.key === key)

// ─── 1 · No page can become unreachable ──────────────────────────────────

test('the default layout shows every nav item exactly once', () => {
  const routes = routesIn(DEFAULT_NAV_SECTIONS)
  for (const item of NAV) {
    assert.equal(
      routes.filter((r) => r === item.to).length, 1,
      `${item.to} should appear exactly once in the default sidebar`,
    )
  }
  assert.equal(routes.length, NAV.length, 'default layout has no extra routes')
})

test('a saved layout that mentions only a handful of pages still shows all of them', () => {
  // Arrange — the worst realistic stale layout: one group, three pages.
  const stale = [
    { kind: 'group', key: 'users_members', tKey: 'nav_group.users_members', items: ['/users', '/beneficiary'] },
    { kind: 'item', to: '/' },
  ]

  // Act
  const sections = reconcileNavSections(stale)

  // Assert — the guard: nothing in NAV may go missing.
  const routes = new Set(routesIn(sections))
  for (const item of NAV) assert.ok(routes.has(item.to), `${item.to} vanished from the sidebar`)
})

test('a saved layout naming a route that no longer exists drops only that route', () => {
  const sections = reconcileNavSections([
    { kind: 'group', key: 'users_members', tKey: 'nav_group.users_members', items: ['/users', '/deleted-page'] },
  ])
  const routes = new Set(routesIn(sections))
  assert.ok(!routes.has('/deleted-page'))
  for (const item of NAV) assert.ok(routes.has(item.to), `${item.to} vanished from the sidebar`)
})

// ─── 2 · Permissions are untouched by a regrouping ───────────────────────

test('superAdminOnly is exactly the set it has always been', () => {
  // Spelled out rather than derived: derived-from-NAV would pass even if
  // someone widened an item, which is the bug this is here to catch.
  const expected = [
    '/staff', '/permissions', '/guest-access', '/terms', '/about',
    '/humanitarian-work', '/contact', '/settings',
  ].sort()
  const actual = NAV.filter((n) => n.superAdminOnly).map((n) => n.to).sort()
  assert.deepEqual(actual, expected)
})

test('gathering the access pages changes no item metadata', () => {
  // /audit-logs moved group; it must still be module-gated, not super-only.
  const audit = NAV.find((n) => n.to === '/audit-logs')
  assert.equal(audit.module, 'audit')
  assert.equal(audit.superAdminOnly, undefined)
  // /guest-access moved group; it must still be super-only.
  assert.equal(NAV.find((n) => n.to === '/guest-access').superAdminOnly, true)
})

// ─── 3 · The access pages are gathered, in the default AND after a save ──

test('every access page sits in the Access & Staff group by default', () => {
  const group = groupNamed(DEFAULT_NAV_SECTIONS, ACCESS_GROUP_KEY)
  assert.ok(group, 'the default layout has an Access & Staff group')
  for (const to of ACCESS_ITEMS) assert.ok(group.items.includes(to), `${to} is not in Access & Staff`)
})

test('Access & Staff sits directly above System Settings, so the two read as one area', () => {
  const access = DEFAULT_NAV_SECTIONS.findIndex((s) => s.kind === 'group' && s.key === ACCESS_GROUP_KEY)
  const system = DEFAULT_NAV_SECTIONS.findIndex((s) => s.kind === 'group' && s.key === 'system_settings')
  assert.equal(system, access + 1)
})

test('the non-access settings pages are still reachable and still in System Settings', () => {
  const system = groupNamed(DEFAULT_NAV_SECTIONS, 'system_settings')
  for (const to of ['/payment-methods', '/donation-types', '/terms', '/about', '/trash', '/field-rules']) {
    assert.ok(system.items.includes(to), `${to} was orphaned out of System Settings`)
  }
})

test("an admin's saved layout is migrated: access pages gather, everything else survives", () => {
  // Arrange — a plausible pre-change customization: the owner had moved
  // Campaigns to the top as a standalone item, renamed nothing, and still had
  // Guest Access buried under Users & Members and Audit Logs under Monitoring.
  const saved = [
    { kind: 'item', to: '/campaigns' },
    { kind: 'group', key: 'users_members', tKey: 'nav_group.users_members', items: ['/users', '/guest-access', '/partners'] },
    { kind: 'group', key: 'monitoring_reports', tKey: 'nav_group.monitoring_reports', items: ['/reports', '/audit-logs'] },
    { kind: 'group', key: 'system_settings', tKey: 'nav_group.system_settings', items: ['/staff', '/permissions', '/trash', '/settings'] },
  ]

  // Act
  const sections = reconcileNavSections(saved)

  // Assert — all five access pages, one group.
  for (const to of ACCESS_ITEMS) {
    const section = sectionOf(sections, to)
    assert.equal(section?.key, ACCESS_GROUP_KEY, `${to} did not land in Access & Staff`)
  }
  // Assert — their other customizations are intact.
  assert.deepEqual(sections[0], { kind: 'item', to: '/campaigns' }, 'the standalone Campaigns item survived')
  assert.deepEqual(groupNamed(sections, 'users_members').items, ['/users', '/partners'])
  assert.deepEqual(groupNamed(sections, 'monitoring_reports').items, ['/reports'])
  assert.deepEqual(groupNamed(sections, 'system_settings').items, ['/trash'])
  // Assert — and still nothing vanished.
  const routes = new Set(routesIn(sections))
  for (const item of NAV) assert.ok(routes.has(item.to), `${item.to} vanished from the sidebar`)
})

test('the gathered group lands directly above the admin\'s System Settings group', () => {
  const sections = reconcileNavSections([
    { kind: 'group', key: 'users_members', tKey: 'nav_group.users_members', items: ['/users', '/guest-access'] },
    { kind: 'group', key: 'system_settings', tKey: 'nav_group.system_settings', items: ['/staff', '/trash'] },
  ])
  // Same relative position as the default layout, wherever the admin moved
  // System Settings to — so every admin ends up with one Settings area.
  const access = sections.findIndex((s) => s.key === ACCESS_GROUP_KEY)
  const system = sections.findIndex((s) => s.key === 'system_settings')
  assert.ok(access >= 0 && system === access + 1)
})

test('with no System Settings group, it lands where the first access page was', () => {
  const sections = reconcileNavSections([
    { kind: 'group', key: 'users_members', tKey: 'nav_group.users_members', items: ['/users', '/guest-access'] },
    { kind: 'group', key: 'marriage', tKey: 'nav_group.marriage', items: ['/marriage'] },
  ])
  assert.equal(sections[0].key, ACCESS_GROUP_KEY)
})

test('a non-access page an admin deliberately filed under Access & Staff is kept', () => {
  const sections = reconcileNavSections([
    { kind: 'group', key: ACCESS_GROUP_KEY, tKey: 'nav_group.access_control', items: ['/staff', '/field-rules'] },
  ])
  const group = groupNamed(sections, ACCESS_GROUP_KEY)
  assert.ok(group.items.includes('/field-rules'), 'their own addition was discarded')
  for (const to of ACCESS_ITEMS) assert.ok(group.items.includes(to))
})

test('reconciling is idempotent — running it on its own output changes nothing', () => {
  const once = reconcileNavSections([
    { kind: 'group', key: 'users_members', tKey: 'nav_group.users_members', items: ['/users', '/guest-access'] },
  ])
  assert.deepEqual(reconcileNavSections(once), once)
})

// ─── 4 · Corrupt input falls back to the default ─────────────────────────

test('null, empty and corrupt saved layouts fall back to the default', () => {
  assert.equal(reconcileNavSections(null), DEFAULT_NAV_SECTIONS)
  assert.equal(reconcileNavSections(undefined), DEFAULT_NAV_SECTIONS)
  assert.equal(reconcileNavSections([]), DEFAULT_NAV_SECTIONS)
  assert.equal(reconcileNavSections('not an array'), DEFAULT_NAV_SECTIONS)

  // Junk entries are skipped, not crashed on — and the guard still fires, so
  // an admin with a mangled setting sees every page rather than none.
  const sections = reconcileNavSections([null, 42, { kind: 'nonsense' }, { kind: 'item', to: '/users' }])
  const routes = new Set(routesIn(sections))
  for (const item of NAV) assert.ok(routes.has(item.to), `${item.to} vanished from the sidebar`)
})

test('a group with an unknown key gets no invented label', () => {
  // A hand-edited setting must not be able to print a raw translation key.
  const sections = reconcileNavSections([
    { kind: 'group', key: 'made_up', items: ['/users'] },
  ])
  assert.ok(!sections.some((s) => s.kind === 'group' && s.key === 'made_up'))
  const routes = new Set(routesIn(sections))
  for (const item of NAV) assert.ok(routes.has(item.to), `${item.to} vanished from the sidebar`)
})
