import { useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { api, describeError } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n, LOCALES } from '../lib/i18n'
import { usePendingCounts, type PendingCounts } from '../lib/pendingCounts'
import { formatPhone } from '../lib/phone'
import { useToast } from '../lib/toast'
import SoundMenu from './SoundMenu'
import ConfirmDialog from './ConfirmDialog'
import { LogOut } from 'lucide-react'

// NAV labels reference i18n keys instead of hardcoded English. The key column
// stays stable; the label is resolved at render time so a locale change
// re-renders the whole sidebar without touching this array.
//
// `countKey` is the field on PendingCounts that drives this item's badge.
// Items without a countKey (Dashboard, Reports, Push, etc.) never show one.
type NavItem = {
  to: string
  tKey: string
  countKey?: keyof Omit<PendingCounts, 'total'>
}

const NAV: NavItem[] = [
  { to: '/',              tKey: 'nav.dashboard' },
  { to: '/users',         tKey: 'nav.users' },
  { to: '/registrations', tKey: 'nav.registrations', countKey: 'registrations' },
  { to: '/campaigns',     tKey: 'nav.campaigns' },
  { to: '/donations',     tKey: 'nav.donations',     countKey: 'donations' },
  { to: '/beneficiary',   tKey: 'nav.beneficiary',   countKey: 'beneficiary' },
  { to: '/marketplace',   tKey: 'nav.marketplace',   countKey: 'marketplace' },
  { to: '/marriage',      tKey: 'nav.marriage',      countKey: 'marriage' },
  { to: '/partners',      tKey: 'nav.partners' },
  { to: '/media',         tKey: 'nav.media' },
  { to: '/community',     tKey: 'nav.community' },
  { to: '/volunteers',    tKey: 'nav.volunteers',    countKey: 'volunteers' },
  { to: '/volunteer-board', tKey: 'nav.volunteer_board' },
  { to: '/missions',      tKey: 'nav.missions' },
  { to: '/sponsorships',  tKey: 'nav.sponsorships',  countKey: 'sponsorships' },
  { to: '/in-kind',       tKey: 'nav.in_kind',       countKey: 'in_kind' },
  { to: '/support',       tKey: 'nav.support',       countKey: 'support' },
  { to: '/notifications', tKey: 'nav.notifications' },
  { to: '/push',          tKey: 'nav.push' },
  { to: '/reports',       tKey: 'nav.reports' },
  { to: '/audit-logs',    tKey: 'nav.audit_logs' },
]

// Show "99+" instead of overflowing the badge with huge digits. ~5 chars max.
function formatBadge(n: number): string {
  if (n <= 0) return ''
  if (n > 99) return '99+'
  return String(n)
}

export default function AppShell() {
  const { user, logout } = useAuth()
  const { t, locale, setLocale } = useI18n()
  const toast = useToast()
  const navigate = useNavigate()
  const location = useLocation()
  const [exporting, setExporting] = useState(false)
  // Phase 27.12 — confirm before signing out so a stray click doesn't end
  // the session.
  const [confirmLogout, setConfirmLogout] = useState(false)
  // Live counts driving the sidebar badges. Updates every 5s via the provider
  // mounted in App.tsx. Counts.total drives the browser tab title prefix below.
  const { counts } = usePendingCounts()

  // Browser-tab title — show "(N) Humanitarian admin" when work is waiting,
  // so an admin who tab-switches away still sees the queue grow. Cleans up
  // back to the plain title when the count hits zero.
  useEffect(() => {
    const base = 'Humanitarian admin'
    document.title = counts.total > 0 ? `(${counts.total}) ${base}` : base
  }, [counts.total])

  async function handleLogout() {
    await logout()
    navigate('/login', { replace: true })
  }

  // Download every business table as a single JSON file. The server already
  // sets Content-Disposition: attachment, but we trigger the download
  // ourselves so we can show a busy state on the button.
  async function handleExport() {
    if (exporting) return
    setExporting(true)
    try {
      // Request as JSON (default for axios) then re-serialize into a Blob —
      // gives us total control over the filename regardless of what the
      // server sent in Content-Disposition.
      const res = await api.get('/api/admin/export/all')
      const json = JSON.stringify(res.data, null, 2)
      const blob = new Blob([json], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const date = new Date().toISOString().slice(0, 10)
      const a = document.createElement('a')
      a.href = url
      a.download = `humanitarian-export-${date}.json`
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

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand" style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <img
            src="/et-logo.png"
            alt="ET"
            width={36}
            height={36}
            style={{ borderRadius: 9, flexShrink: 0 }}
          />
          <div>
            <strong>Humanitarian</strong>
            <div className="muted">admin</div>
          </div>
        </div>
        <nav>
          {NAV.map((n) => {
            const isActive = n.to === '/'
              ? location.pathname === '/'
              : location.pathname.startsWith(n.to)
            const rawCount = n.countKey ? counts[n.countKey] : 0
            const badge = formatBadge(rawCount)
            return (
              <NavLink
                key={n.to}
                to={n.to}
                end={n.to === '/'}
                className="nav-item"
                aria-label={
                  badge
                    ? t('shell.pending_aria', { label: t(n.tKey), count: rawCount })
                    : undefined
                }
              >
                {/* Animated active pill — layoutId="nav-active" makes framer
                    move the same physical element between siblings, producing
                    a smooth slide between the previous active item and the new
                    one. */}
                {isActive && (
                  <motion.span
                    className="nav-active-bg"
                    layoutId="nav-active"
                    transition={{ type: 'spring', stiffness: 380, damping: 30 }}
                  />
                )}
                <span className="nav-item-label">{t(n.tKey)}</span>
                {/* Pending-count badge. Hidden via CSS when count is 0 so we
                    don't render a stack of empty pills on a fresh database. */}
                {badge && (
                  <span
                    className="nav-badge"
                    title={t('shell.pending_count', { count: rawCount })}
                    aria-hidden="true"
                  >
                    {badge}
                  </span>
                )}
              </NavLink>
            )
          })}
        </nav>

        {/* Sidebar foot — pinned to the bottom via margin-top:auto on the
            wrapper. The Export button is amber to stand out from the
            emerald primary used everywhere else; this is intentionally a
            "different kind" of action (data export, not a daily op). */}
        <div className="sidebar-foot">
          <button
            className="amber export-btn"
            onClick={handleExport}
            disabled={exporting}
            title={t('shell.export_title')}
          >
            <span aria-hidden="true" style={{ fontSize: 14, lineHeight: 1 }}>↓</span>
            {exporting ? t('shell.exporting') : t('shell.export_db')}
          </button>
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
          <div className="user-chip">
            {/* Initial circle — derived from user_id since we may not have
                a parsed full_name on every page render. */}
            <div className="user-chip-avatar" aria-hidden="true">
              {String(user?.user_id ?? '?').slice(-2)}
            </div>
            <div className="user-chip-meta">
              <span className="user-chip-id">User #{user?.user_id}</span>
              <span className="muted">{formatPhone(user?.phone)}</span>
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
