import { useEffect, useState, useRef } from 'react'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { AdminNotification, AdminPageResp } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import ExportCsvButton from '../components/ExportCsvButton'
import { downloadCsv, type CsvColumn } from '../lib/csv'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useToast } from '../lib/toast'

// Flat CSV shape for a notification row (Phase 7 · M-53).
const NOTIFICATION_CSV_COLUMNS: CsvColumn<AdminNotification>[] = [
  { header: 'id', get: (n) => n.id },
  { header: 'target', get: (n) => n.user_id ? `user #${n.user_id}` : n.role_id ? `role ${n.role_id}` : 'broadcast' },
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

export default function NotificationsPage() {
  const [page, setPage] = useState(1)
  const [category, setCategory] = useState('')
  const [readStatus, setReadStatus] = useState('all')
  const [resp, setResp] = useState<AdminPageResp<AdminNotification> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  // Phase 27 — `refreshTick` triggers the load effect to re-fire from
  // the live-poll below, without needing a separate fetch path.
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const toast = useToast()

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`notifications-${new Date().toISOString().slice(0, 10)}.csv`, rows, NOTIFICATION_CSV_COLUMNS)
  }

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

  const columns: Column<AdminNotification>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (n) => <strong>#{n.id}</strong> },
    {
      key: 'target', header: t('col.target'),
      cell: (n) =>
        n.user_id ? `user #${n.user_id}` :
          n.role_id ? `role ${n.role_id}` :
            <span className="badge">{t('page.notifications.broadcast')}</span>,
    },
    {
      key: 'title', header: t('col.title'),
      cell: (n) => (
        <div className="cell-stack">
          <strong>{n.title}</strong>
          {n.title_ar && <span className="muted">{n.title_ar}</span>}
        </div>
      ),
    },
    {
      key: 'body', header: t('col.body'),
      cell: (n) => <span style={{ whiteSpace: 'normal' }}>{n.body.length > 100 ? n.body.slice(0, 100) + '…' : n.body}</span>,
    },
    { key: 'type', header: t('col.type'), cell: (n) => n.notification_type ? <code style={{ background: 'transparent', padding: 0 }}>{n.notification_type}</code> : <span className="muted">—</span> },
    {
      key: 'cat', header: t('col.category'),
      cell: (n) => <span className={`badge ${categoryBadge(n.notification_category)}`}>{statusLabel(n.notification_category)}</span>,
    },
    { key: 'prio', header: t('col.pri'), align: 'right', cell: (n) => n.priority },
    { key: 'read', header: t('col.read'), cell: (n) => n.is_read === 1 ? <span className="badge ok">{t('common.yes')}</span> : <span className="badge off">{t('common.no')}</span> },
    { key: 'created', header: t('col.created'), cell: (n) => <span className="muted">{n.created_at?.slice(0, 16).replace('T', ' ')}</span> },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.notifications.title')}</h1>
          <p className="muted">{resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}</p>
        </div>
        <div className="row">
          <select value={category} onChange={(e) => { setCategory(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            {CATEGORIES.map(c => <option key={c} value={c}>{c === '' ? t('filter.all_categories') : statusLabel(c)}</option>)}
          </select>
          <select value={readStatus} onChange={(e) => { setReadStatus(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            {READ.map(r => (
              <option key={r} value={r}>
                {r === 'all' ? t('page.notifications.read_all') : r === 'unread' ? t('page.notifications.read_unread') : t('page.notifications.read_read')}
              </option>
            ))}
          </select>
          <ExportCsvButton onExport={exportCsv} />
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<AdminNotification> rows={resp?.items ?? []} columns={columns} rowKey={(n) => n.id} loading={loading} empty={t('empty.notifications')} />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
    </div>
  )
}
