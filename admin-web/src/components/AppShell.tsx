import { useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { api, describeError, canExportData, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n, LOCALES } from '../lib/i18n'
import { usePendingCounts } from '../lib/pendingCounts'
import { formatPhone } from '../lib/phone'
import { RESOURCE_LABELS } from '../lib/resourceLabels'
import { useToast } from '../lib/toast'
import { navByTo, DEFAULT_NAV_SECTIONS, reconcileNavSections, type NavItem, type NavSection } from '../lib/navLayout'
import SoundMenu from './SoundMenu'
import ConfirmDialog from './ConfirmDialog'
import TopActionBar from './TopActionBar'
import { ChevronDown, ChevronRight, LogOut, Menu, PanelLeftClose, PanelLeftOpen } from 'lucide-react'

// Show "99+" instead of overflowing the badge with huge digits. ~5 chars max.
function formatBadge(n: number): string {
  if (n <= 0) return ''
  if (n > 99) return '99+'
  return String(n)
}

// A top-level component (not nested inside AppShell) so its identity stays
// stable across AppShell's frequent re-renders (live pending-count polling
// every 5s) — a function defined INSIDE AppShell would get a new identity
// every render, forcing React to remount every nav link instead of just
// re-rendering it, which breaks the layoutId="nav-active" slide animation
// and re-runs mount transitions for no reason.
function NavItemLink({ n, nested }: { n: NavItem; nested?: boolean }) {
  const { t } = useI18n()
  const location = useLocation()
  const { counts } = usePendingCounts()
  const sectionMatchPath = location.pathname.startsWith('/detail/')
    ? RESOURCE_LABELS[location.pathname.split('/')[2]]?.list ?? location.pathname
    : location.pathname
  const isActive = n.to === '/' ? location.pathname === '/' : sectionMatchPath.startsWith(n.to)
  const rawCount = n.countKey ? counts[n.countKey] : 0
  const badge = formatBadge(rawCount)
  return (
    <NavLink
      to={n.to}
      end={n.to === '/'}
      className={`nav-item${nested ? ' nav-item-nested' : ''}`}
      aria-label={badge ? t('shell.pending_aria', { label: t(n.tKey), count: rawCount }) : undefined}
    >
      {/* Animated active pill — layoutId="nav-active" makes framer move the
          same physical element between siblings, producing a smooth slide
          between the previous active item and the new one. */}
      {isActive && (
        <motion.span
          className="nav-active-bg"
          layoutId="nav-active"
          transition={{ type: 'spring', stiffness: 380, damping: 30 }}
        />
      )}
      <span className="nav-item-label">{t(n.tKey)}</span>
      {/* Pending-count badge. Hidden via CSS when count is 0 so we don't
          render a stack of empty pills on a fresh database. */}
      {badge && (
        <span className="nav-badge" title={t('shell.pending_count', { count: rawCount })} aria-hidden="true">
          {badge}
        </span>
      )}
    </NavLink>
  )
}

export default function AppShell() {
  const { user, logout } = useAuth()
  const { t, locale, setLocale } = useI18n()
  const toast = useToast()
  const navigate = useNavigate()
  const location = useLocation()
  // Note #11 — the sidebar used to lose its highlight on /detail/:resource/:id
  // (the View page) because that path doesn't start with any nav item's `to`.
  // Resolve it back to the owning section's list path (via the shared
  // RESOURCE_LABELS map — several resources live under a section whose path
  // doesn't textually match, e.g. products/orders → /marketplace) before
  // matching, so the highlight stays put while viewing a record.
  const sectionMatchPath = location.pathname.startsWith('/detail/')
    ? RESOURCE_LABELS[location.pathname.split('/')[2]]?.list ?? location.pathname
    : location.pathname
  const [exporting, setExporting] = useState(false)
  // Phase 27.12 — confirm before signing out so a stray click doesn't end
  // the session.
  const [confirmLogout, setConfirmLogout] = useState(false)
  // Live counts driving the sidebar badges. Updates every 5s via the provider
  // mounted in App.tsx. Counts.total drives the browser tab title prefix below.
  const { counts } = usePendingCounts()

  // Note #2 follow-up — collapsible sidebar. Wide tables (esp. Users, with
  // 5 stacked status dropdowns) lose columns off-screen; hiding the 256px
  // sidebar gives that width back to the content. Persisted so the choice
  // survives a reload/relogin.
  const [sidebarCollapsed, setSidebarCollapsed] = useState(
    () => localStorage.getItem('humanitarian.admin.sidebar_collapsed') === '1',
  )
  useEffect(() => {
    localStorage.setItem('humanitarian.admin.sidebar_collapsed', sidebarCollapsed ? '1' : '0')
  }, [sidebarCollapsed])

  // Responsive pass — on phone/tablet widths the sidebar becomes an overlay
  // drawer instead of a grid column (see the max-width:768px block in
  // index.css), opened via the hamburger button below and closed by tapping
  // the scrim or navigating anywhere. Deliberately NOT persisted like
  // sidebarCollapsed — a drawer should always start closed on a fresh load.
  const [mobileNavOpen, setMobileNavOpen] = useState(false)
  useEffect(() => {
    setMobileNavOpen(false)
  }, [location.pathname])

  // Note #29 — which nav groups the admin has manually opened, persisted the
  // same way sidebarCollapsed is. Whichever group contains the CURRENT page
  // is always shown open on top of this (computed at render time below) —
  // this state only remembers groups opened out of that context.
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(() => {
    try {
      const raw = localStorage.getItem('humanitarian.admin.sidebar_open_groups')
      return raw ? new Set(JSON.parse(raw)) : new Set()
    } catch {
      return new Set()
    }
  })
  useEffect(() => {
    localStorage.setItem('humanitarian.admin.sidebar_open_groups', JSON.stringify([...expandedGroups]))
  }, [expandedGroups])
  const toggleGroup = (key: string) =>
    setExpandedGroups((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })

  // Section 24 — effective per-module permissions for THIS user's tier. Drives
  // menu-access-control: a module the tier can't `view` is hidden entirely.
  // null while loading (show everything to avoid a flash of an empty sidebar);
  // once loaded, modules with view=false are filtered out.
  const [viewable, setViewable] = useState<Record<string, boolean> | null>(null)
  useEffect(() => {
    let cancelled = false
    api
      .get<{ permissions: Record<string, Record<string, boolean>> }>('/api/admin/permissions/me')
      .then((r) => {
        if (cancelled) return
        const map: Record<string, boolean> = {}
        for (const [mod, actions] of Object.entries(r.data.permissions ?? {})) {
          map[mod] = actions?.view !== false
        }
        setViewable(map)
      })
      .catch(() => { if (!cancelled) setViewable(null) })
    return () => { cancelled = true }
  }, [])

  // Note #29 follow-up — a Super-Admin can reorder/regroup the sidebar from
  // Dashboard Settings. Starts as the built-in default so the sidebar never
  // flashes empty while this loads; reconcileNavSections both validates the
  // saved value and merges in any nav item it doesn't mention (e.g. a page
  // added after the layout was last customized), so a stale/corrupt saved
  // layout can only ever reorder pages, never hide one.
  const [navSections, setNavSections] = useState<NavSection[]>(DEFAULT_NAV_SECTIONS)
  useEffect(() => {
    let cancelled = false
    api
      .get<{ layout: NavSection[] | null }>('/api/admin/settings/nav-layout')
      .then((r) => { if (!cancelled) setNavSections(reconcileNavSections(r.data.layout)) })
      .catch(() => { /* keep the built-in default */ })
    return () => { cancelled = true }
  }, [])

  // Note #5 — idle auto-lock duration, previously a hardcoded 20-minute
  // constant (itself a relaxation of the original 2-minute spec value, which
  // logged staff out mid-task constantly). Now the Main Admin can tune it
  // from Dashboard Settings; this fetches the current value once on mount.
  // 20 stays the fallback so behavior is unchanged until an admin sets one.
  const [idleMinutes, setIdleMinutes] = useState(20)
  useEffect(() => {
    let cancelled = false
    api
      .get<{ minutes: number }>('/api/admin/settings/session-timeout')
      .then((r) => {
        if (!cancelled && typeof r.data.minutes === 'number' && r.data.minutes > 0) {
          setIdleMinutes(r.data.minutes)
        }
      })
      .catch(() => { /* keep the 20-minute fallback */ })
    return () => { cancelled = true }
  }, [])

  // Section 24 — idle auto-lock. After idleMinutes of no user activity the
  // session is ended and the admin must re-authenticate. Any real
  // interaction resets the timer.
  useEffect(() => {
    let timer: number | undefined
    const idleMs = idleMinutes * 60 * 1000
    const reset = () => {
      if (timer) window.clearTimeout(timer)
      timer = window.setTimeout(async () => {
        await logout()
        toast.info(t('shell.idle_locked'))
        navigate('/login', { replace: true })
      }, idleMs)
    }
    const events: (keyof WindowEventMap)[] = ['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart', 'click']
    events.forEach((e) => window.addEventListener(e, reset, { passive: true }))
    reset()
    return () => {
      if (timer) window.clearTimeout(timer)
      events.forEach((e) => window.removeEventListener(e, reset))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idleMinutes])

  // Browser-tab title — show "(N) Humanitarian admin" when work is waiting,
  // so an admin who tab-switches away still sees the queue grow. Cleans up
  // back to the plain title when the count hits zero.
  useEffect(() => {
    const base = 'BalanceNex admin'
    document.title = counts.total > 0 ? `(${counts.total}) ${base}` : base
  }, [counts.total])

  async function handleLogout() {
    await logout()
    navigate('/login', { replace: true })
  }

  // Download every business table as a single JSON file. The server already
  // sets Content-Disposition: attachment, but we trigger the download
  // ourselves so we can show a busy state on the button.
  //
  // Note #27 — this used to fire on a single click with only the sidebar's
  // Super-Admin-only visibility as protection. PIN-gated the same way
  // Purge/Restore already are: prompt for the admin's own password and let
  // the backend verify it before it will dump the database.
  async function handleExport() {
    if (exporting) return
    const pin = window.prompt(t('export.pin_prompt'))
    if (pin == null) return
    if (!pin.trim()) { toast.error(t('export.pin_required')); return }
    setExporting(true)
    try {
      // Request as JSON (default for axios) then re-serialize into a Blob —
      // gives us total control over the filename regardless of what the
      // server sent in Content-Disposition.
      const res = await api.post('/api/admin/export/all', { password: pin })
      const json = JSON.stringify(res.data, null, 2)
      const blob = new Blob([json], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const date = new Date().toISOString().slice(0, 10)
      const a = document.createElement('a')
      a.href = url
      a.download = `balancenex-export-${date}.json`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)

      const tableCount = Object.keys(res.data.row_counts || {}).length
      const rowCount = Object.values(res.data.row_counts || {}).reduce(
        (s: number, n) => s + (typeof n === 'number' ? n : 0),
        0,
      )
      toast.success(t('shell.export_result', { tables: tableCount, rows: rowCount }))
    } catch (err) {
      toast.error(describeError(err))
    } finally {
      setExporting(false)
    }
  }

  const isNavItemVisible = (n: NavItem) =>
    (!n.adminOnly || canExportData(user)) &&
    (!n.superAdminOnly || isSuperAdmin(user)) &&
    // Menu access control (Section 24): hide modules the tier can't view.
    (!n.module || viewable === null || viewable[n.module] !== false)
  const isItemActive = (n: NavItem) =>
    n.to === '/' ? location.pathname === '/' : sectionMatchPath.startsWith(n.to)

  return (
    <div className={`app-shell${sidebarCollapsed ? ' sidebar-collapsed' : ''}${mobileNavOpen ? ' mobile-nav-open' : ''}`}>
      {/* Mobile-only scrim behind the drawer; tapping it closes the same way
          tapping outside any other overlay in this app does. */}
      {mobileNavOpen && (
        <div
          className="mobile-nav-scrim"
          onClick={() => setMobileNavOpen(false)}
          aria-hidden="true"
        />
      )}
      <aside className="sidebar" aria-hidden={sidebarCollapsed && !mobileNavOpen}>
        <div className="brand" style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <img
            src="/et-logo.png"
            alt="ET"
            width={36}
            height={36}
            style={{ borderRadius: 9, flexShrink: 0 }}
          />
          <div>
            <strong>BalanceNex</strong>
            <div className="muted">admin</div>
          </div>
        </div>
        <nav>
          {navSections.map((section) => {
            if (section.kind === 'item') {
              const n = navByTo.get(section.to)
              if (!n || !isNavItemVisible(n)) return null
              return <NavItemLink key={n.to} n={n} />
            }
            // Group: only render if it has at least one visible item left
            // after permission filtering, so a tier that can't see anything
            // inside a group never sees a header pointing at an empty box.
            const items = section.items
              .map((to) => navByTo.get(to))
              .filter((n): n is NavItem => !!n && isNavItemVisible(n))
            if (items.length === 0) return null
            // The group containing the current page is always shown open,
            // regardless of expandedGroups state — landing on a page should
            // never hide the very item you're looking at.
            const hasActiveItem = items.some((n) => isItemActive(n))
            const open = hasActiveItem || expandedGroups.has(section.key)
            const groupCount = items.reduce(
              (sum, n) => sum + (n.countKey ? counts[n.countKey] : 0), 0,
            )
            const groupBadge = formatBadge(groupCount)
            return (
              <div key={section.key} className="nav-group">
                <button
                  type="button"
                  className="nav-group-header"
                  onClick={() => toggleGroup(section.key)}
                  aria-expanded={open}
                >
                  {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                  <span className="nav-item-label">{t(section.tKey)}</span>
                  {groupBadge && (
                    <span
                      className="nav-badge"
                      title={t('shell.pending_count', { count: groupCount })}
                      aria-hidden="true"
                    >
                      {groupBadge}
                    </span>
                  )}
                </button>
                {open && (
                  <div className="nav-group-items">
                    {items.map((n) => <NavItemLink key={n.to} n={n} nested />)}
                  </div>
                )}
              </div>
            )
          })}
        </nav>

        {/* Sidebar foot — pinned to the bottom via margin-top:auto on the
            wrapper. The Export button is amber to stand out from the
            emerald primary used everywhere else; this is intentionally a
            "different kind" of action (data export, not a daily op). */}
        <div className="sidebar-foot">
          {/* Raw DB (JSON) export is restricted to the Super-Admin ONLY;
              lower tiers (including plain admin) never see the button, and the
              backend enforces the same via RequireSuperAdmin. */}
          {isSuperAdmin(user) && (
            <button
              className="amber export-btn"
              onClick={handleExport}
              disabled={exporting}
              title={t('shell.export_title')}
            >
              <span aria-hidden="true" style={{ fontSize: 14, lineHeight: 1 }}>↓</span>
              {exporting ? t('shell.exporting') : t('shell.export_db')}
            </button>
          )}
          {/* Phase 27.12 — logout moved here from the topbar and given a
              filled danger color so it reads as a deliberate sign-out
              action, sitting right under the Export button. */}
          <button
            className="danger logout-btn"
            onClick={() => setConfirmLogout(true)}
            title={t('shell.logout_title')}
          >
            <LogOut size={15} strokeWidth={2.4} />
            {t('nav.logout')}
          </button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <div className="row" style={{ alignItems: 'center', gap: 12 }}>
            {/* Responsive pass — hamburger for the phone/tablet drawer.
                CSS-only visible below the mobile breakpoint (index.css);
                the desktop collapse toggle right after it is the mirror —
                CSS-hidden below that same breakpoint, since a permanent
                collapse choice doesn't make sense once the sidebar is an
                overlay instead of a layout column. */}
            <button
              type="button"
              className="mobile-nav-toggle-btn"
              onClick={() => setMobileNavOpen((o) => !o)}
              title={t('shell.sidebar_show')}
              aria-label={t('shell.sidebar_show')}
            >
              <Menu size={19} strokeWidth={2.3} />
            </button>
            {/* Note #2 — sidebar collapse toggle. Lives in the topbar (not
                inside the sidebar) so it's reachable in BOTH states — a
                button that only exists inside the thing it hides would trap
                the admin in the collapsed state. */}
            <button
              type="button"
              className="sidebar-toggle-btn"
              onClick={() => setSidebarCollapsed((c) => !c)}
              title={sidebarCollapsed ? t('shell.sidebar_show') : t('shell.sidebar_hide')}
              aria-label={sidebarCollapsed ? t('shell.sidebar_show') : t('shell.sidebar_hide')}
            >
              {sidebarCollapsed ? <PanelLeftOpen size={19} strokeWidth={2.3} /> : <PanelLeftClose size={19} strokeWidth={2.3} />}
              <span>{sidebarCollapsed ? t('shell.sidebar_show') : t('shell.sidebar_hide')}</span>
            </button>
            <div className="user-chip">
              {/* Initial circle — derived from user_id since we may not have
                  a parsed full_name on every page render. */}
              <div className="user-chip-avatar" aria-hidden="true">
                {String(user?.user_id ?? '?').slice(-2)}
              </div>
              <div className="user-chip-meta">
                <span className="user-chip-id">{t('common.user_ref', { id: user?.user_id ?? 0 })}</span>
                <span className="muted">{formatPhone(user?.phone)}</span>
              </div>
            </div>
          </div>
          <div className="row" style={{ alignItems: 'center', gap: 8 }}>
            {/* Speaker icon — opens a dropdown with sound on/off, test
                chime, and OS-notification opt-in. Always available so an
                admin can mute/unmute from any page. */}
            <SoundMenu />
            <select
              value={locale}
              onChange={(e) => setLocale(e.target.value as typeof locale)}
              style={{ width: 'auto' }}
              aria-label={t('shell.language')}
            >
              {LOCALES.map((l) => (
                <option key={l.code} value={l.code}>{l.nativeLabel}</option>
              ))}
            </select>
          </div>
        </header>
        <div className="content">
          {/* Unified top action bar (global notice #7) — shown on every page. */}
          <TopActionBar />
          {/* Route transitions: each pathname becomes a new key, so
              AnimatePresence treats it as a fresh element with its own
              enter/exit lifecycle. */}
          <AnimatePresence mode="wait">
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.18, ease: 'easeOut' }}
            >
              <Outlet />
            </motion.div>
          </AnimatePresence>
        </div>
      </div>

      {/* Phase 27.12 — logout confirmation. The button only opens this;
          the actual sign-out runs on confirm. */}
      <ConfirmDialog
        open={confirmLogout}
        title={t('nav.logout')}
        message={t('shell.logout_message')}
        confirmLabel={t('nav.logout')}
        onConfirm={async () => {
          await handleLogout()
        }}
        onCancel={() => setConfirmLogout(false)}
      />
    </div>
  )
}
