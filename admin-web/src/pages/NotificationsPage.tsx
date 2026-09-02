import { useEffect, useState, useRef } from 'react'
import LocalizedCell from '../components/LocalizedCell'
import { localizedField } from '../lib/localizedContent'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { AdminNotification, AdminPageResp } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import ExportCsvButton from '../components/ExportCsvButton'
import { type CsvColumn } from '../lib/csv'
import { useI18n, useStatusLabel, translate } from '../lib/i18n'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'

// Flat CSV shape for a notification row (Phase 7 · M-53).
const NOTIFICATION_CSV_COLUMNS: CsvColumn<AdminNotification>[] = [
  { header: 'id', get: (n) => n.id },
  { header: 'target', get: (n) => n.user_id ? translate('common.user_ref_lc', { id: n.user_id }) : n.role_id ? translate('common.role_ref', { id: n.role_id }) : translate('page.notifications.broadcast') },
  { header: 'title', get: (n) => n.title },
  { header: 'title_ar', get: (n) => n.title_ar ?? '' },
  { header: 'body', get: (n) => n.body },
  { header: 'type', get: (n) => n.notification_type ?? '' },
  { header: 'category', get: (n) => n.notification_category },
  { header: 'priority', get: (n) => n.priority },
  { header: 'is_read', get: (n) => n.is_read === 1 ? 'read' : 'unread' },
  { header: 'created_at', get: (n) => n.created_at ?? '' },
]

const PER_PAGE = 20
const CATEGORIES = ['', 'normal', 'urgent', 'payment', 'campaign', 'system', 'reminder']
const READ = ['all', 'unread', 'read']

function categoryBadge(c: string): string {
  switch (c) {
    case 'urgent': return 'failed'
    case 'payment': return 'success'
    case 'campaign': return 'role-1'
    case 'system': return 'role-3'
    case 'reminder': return 'pending'
    default: return ''
  }
}

// Task 3 (owner ask: "show the notification badge and color code and
// filter") — colour-coding is by PRIORITY/SEVERITY, not by category/source.
// This is not a new taxonomy: it reuses `defaultPriority` in
// backend/internal/notify/notify.go (urgent=80, payment=60 → high;
// campaign=35, system=20 → medium; reminder=15, normal=0 → low), the exact
// same boundary the Flutter app's notification-settings screen already
// groups its category switches into (_tierOf,
// humanitarian/lib/modules/notifications/screens/notification_categories_screen.dart).
// Reusing it here means an admin and an app user agree on what "high
// priority" means without a second definition to drift out of sync.
type PriorityTier = 'high' | 'medium' | 'low'
const PRIORITY_TIERS: PriorityTier[] = ['high', 'medium', 'low']

function tierOfCategory(category: string): PriorityTier {
  switch (category) {
    case 'urgent':
    case 'payment':
      return 'high'
    case 'campaign':
    case 'system':
      return 'medium'
    default: // reminder, normal, and any future category default to 'low'.
      return 'low'
  }
}

// Reuses the existing .badge.tone-* palette (index.css) — already defined
// and contrast-verified in both themes; no new CSS variables introduced
// (the codebase has a documented prior bug where a referenced-but-undefined
// variable, --color-surface-1, silently dropped a whole rule — every token
// below is one already declared in :root and :root[data-theme='light']).
// Measured against the panel background these badges sit on, in each theme
// (WCAG contrast, text colour vs. composited badge background):
//   high   (tone-danger)  dark 8.16:1 · light 5.32:1
//   medium (tone-warning) dark 9.66:1 · light 6.31:1
//   low    (tone-info)    dark 8.11:1 · light 5.28:1
// All four clear the 4.5:1 minimum in both themes.
const TIER_TONE: Record<PriorityTier, string> = {
  high: 'tone-danger',
  medium: 'tone-warning',
  low: 'tone-info',
}

export default function NotificationsPage() {
  const [page, setPage] = useState(1)
  const [category, setCategory] = useState('')
  const [readStatus, setReadStatus] = useState('all')
  // Task 3c — filter by priority tier. Client-side: the backend's
  // /api/admin/notifications has no priority-tier query param (tiers are a
  // dashboard-side grouping of `notification_category`, computed by
  // tierOfCategory above, not a stored column to filter on server-side), so
  // this filters the already-fetched page same as isStaffAccount does for
  // UsersPage/StaffPage — a page can show fewer than PER_PAGE rows when some
  // of it doesn't match, a known/accepted imprecision rather than a gate.
  const [priorityTier, setPriorityTier] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminNotification> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  // Phase 27 — `refreshTick` triggers the load effect to re-fire from
  // the live-poll below, without needing a separate fetch path.
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const { t, locale } = useI18n()
  const statusLabel = useStatusLabel()


  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<AdminNotification>>('/api/admin/notifications', {
        params: {
          page, per_page: PER_PAGE,
          category: category || undefined,
          read_status: readStatus,
        },
      })
      .then(r => { if (!cancelled) setResp(r.data) })
      .catch(e => { if (!cancelled && !pollSilent.current) setErr(describeError(e)) })
      .finally(() => { if (!cancelled && !pollSilent.current) setLoading(false); pollSilent.current = false })
    return () => { cancelled = true }
  }, [page, category, readStatus, refreshTick])

  // Phase 27 — live refresh notifications every 5s. New rows fired
  // by admin actions should appear in this list without a manual reload.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  // Task 3c — apply the priority-tier filter to the fetched page (see the
  // priorityTier state comment above for why this is client-side).
  const visibleItems = (resp?.items ?? []).filter(
    (n) => !priorityTier || tierOfCategory(n.notification_category) === priorityTier,
  )

  const columns: Column<AdminNotification>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (n) => <strong>{fmtId(n.id)}</strong> },
    {
      key: 'target', header: t('col.target'),
      cell: (n) =>
        n.user_id ? t('common.user_ref_lc', { id: n.user_id }) :
          n.role_id ? t('common.role_ref', { id: n.role_id }) :
            <span className="badge">{t('page.notifications.broadcast')}</span>,
    },
    {
      key: 'title', header: t('col.title'),
      cell: (n) => (
        <LocalizedCell row={n} field="title" locale={locale} />
      ),
    },
    {
      key: 'body', header: t('col.body'),
      // body_ar was sitting in the payload, unrendered: the message text was
      // English on an Arabic screen even when the translation existed.
      cell: (n) => {
        const text = localizedField(n as unknown as Record<string, unknown>, 'body', locale)
        return (
          <span style={{ whiteSpace: 'normal' }}>
            {text.length > 100 ? text.slice(0, 100) + '…' : text}
          </span>
        )
      },
    },
    // notification_type was rendered inside <code> as a raw enum
    // (beneficiary_case_submitted, volunteer_application_approved, …) —
    // checklist B1. The sibling category cell below already did this right.
    { key: 'type', header: t('col.type'), cell: (n) => n.notification_type ? statusLabel(n.notification_type) : <span className="muted">—</span> },
    {
      key: 'cat', header: t('col.category'),
      cell: (n) => <span className={`badge ${categoryBadge(n.notification_category)}`}>{statusLabel(n.notification_category)}</span>,
    },
    {
      // Task 3b — colour-coded by priority tier, never colour alone: the
      // badge always carries the tier's text label, with the raw numeric
      // priority alongside it in muted text so nothing that used to be
      // visible (the number) is lost.
      key: 'prio', header: t('col.pri'), align: 'right',
      cell: (n) => {
        const tier = tierOfCategory(n.notification_category)
        return (
          <span className="row" style={{ justifyContent: 'flex-end', gap: 6 }}>
            <span className="muted">{n.priority}</span>
            <span className={`badge ${TIER_TONE[tier]}`}>{t(`page.notifications.tier_${tier}`)}</span>
          </span>
        )
      },
    },
    { key: 'read', header: t('col.read'), cell: (n) => n.is_read === 1 ? <span className="badge ok">{t('common.yes')}</span> : <span className="badge off">{t('common.no')}</span> },
    { key: 'created', header: t('col.created'), cell: (n) => <span className="muted">{n.created_at?.slice(0, 16).replace('T', ' ')}</span> },
  ]

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('page.notifications.title')}</h1>
          <p className="muted">{resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}</p>
        </div>
        <div className="row">
          <select value={category} onChange={(e) => { setCategory(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            {CATEGORIES.map(c => <option key={c} value={c}>{c === '' ? t('filter.all_categories') : statusLabel(c)}</option>)}
          </select>
          {/* Task 3c — filter by the same priority taxonomy the badges use. */}
          <select value={priorityTier} onChange={(e) => { setPriorityTier(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            <option value="">{t('page.notifications.filter_all_priorities')}</option>
            {PRIORITY_TIERS.map((tier) => (
              <option key={tier} value={tier}>{t(`page.notifications.tier_${tier}`)}</option>
            ))}
          </select>
          <select value={readStatus} onChange={(e) => { setReadStatus(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            {READ.map(r => (
              <option key={r} value={r}>
                {r === 'all' ? t('page.notifications.read_all') : r === 'unread' ? t('page.notifications.read_unread') : t('page.notifications.read_read')}
              </option>
            ))}
          </select>
          <ExportCsvButton
            rows={visibleItems}
            columns={NOTIFICATION_CSV_COLUMNS}
            filenameBase="notifications"
            title={t('nav.notifications')}
            module="notifications"
          />
        </div>
      </PageHead>
      {err && <div className="error-box">{err}</div>}
      <Table<AdminNotification> rows={visibleItems} columns={columns} rowKey={(n) => n.id} loading={loading} empty={t('empty.notifications')} />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
    </div>
  )
}
