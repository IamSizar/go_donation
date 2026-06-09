import { useEffect, useState, useRef } from 'react'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { AdminNotification, AdminPageResp } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import { useI18n } from '../lib/i18n'

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
      cell: (n) => <span className={`badge ${categoryBadge(n.notification_category)}`}>{n.notification_category}</span>,
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
            {CATEGORIES.map(c => <option key={c} value={c}>{c === '' ? t('filter.all_categories') : c}</option>)}
          </select>
          <select value={readStatus} onChange={(e) => { setReadStatus(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            {READ.map(r => (
              <option key={r} value={r}>
                {r === 'all' ? t('page.notifications.read_all') : r === 'unread' ? t('page.notifications.read_unread') : t('page.notifications.read_read')}
              </option>
            ))}
          </select>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<AdminNotification> rows={resp?.items ?? []} columns={columns} rowKey={(n) => n.id} loading={loading} empty={t('empty.notifications')} />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
    </div>
  )
}
