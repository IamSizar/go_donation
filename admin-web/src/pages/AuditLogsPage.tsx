import { useEffect, useMemo, useState } from 'react'
import { api, describeError } from '../lib/api'
import type { AdminAuditLog, AdminPageResp } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import { downloadCsv, type CsvColumn } from '../lib/csv'

const PER_PAGE = 30

const AUDIT_CSV_COLUMNS: CsvColumn<AdminAuditLog>[] = [
  { header: 'id', get: (a) => a.id },
  { header: 'created_at', get: (a) => a.created_at },
  { header: 'user_id', get: (a) => a.user_id },
  { header: 'changed_field', get: (a) => a.changed_field },
  { header: 'old_value', get: (a) => a.old_value },
  { header: 'new_value', get: (a) => a.new_value },
  { header: 'actor_source', get: (a) => a.actor_source },
  { header: 'actor_user_id', get: (a) => a.actor_user_id },
  { header: 'metadata_json', get: (a) => a.metadata_json },
]

// Maps the audit `actor_source` value to a badge colour class. The set of
// sources is finite in practice (admin, mobile_app, system, …), but anything
// unrecognised falls through to a neutral colour.
function actorClass(src: string): string {
  switch (src) {
    case 'admin': return 'role-1'
    case 'system': return 'role-3'
    case 'mobile_app': return 'pending'
    case 'cron': return 'role-3'
    default: return ''
  }
}

export default function AuditLogsPage() {
  const [page, setPage] = useState(1)
  const [userIDFilter, setUserIDFilter] = useState('')
  const [field, setField] = useState('')
  const [actor, setActor] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminAuditLog> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<number | null>(null)
  const toast = useToast()
  const { t } = useI18n()

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<AdminPageResp<AdminAuditLog>>('/api/admin/audit_logs', {
        params: {
          page, per_page: PER_PAGE,
          user_id: userIDFilter || undefined,
          field: field || undefined,
        },
      })
      .then(r => { if (!cancelled) setResp(r.data) })
      .catch(e => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [page, userIDFilter, field])

  const itemsAll = resp?.items ?? []
  // Client-side actor filter — the backend doesn't index actor_source.
  const items = useMemo(() => actor ? itemsAll.filter((a) => a.actor_source === actor) : itemsAll, [itemsAll, actor])
  const fields = useMemo(() => Array.from(new Set(itemsAll.map(a => a.changed_field))).sort(), [itemsAll])
  const actors = useMemo(() => Array.from(new Set(itemsAll.map(a => a.actor_source))).sort(), [itemsAll])

  const exportCsv = () => {
    if (items.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`audit-${new Date().toISOString().slice(0, 10)}.csv`, items, AUDIT_CSV_COLUMNS)
  }

  // Highlight the changed_field as a code chip; render old → new with a
  // visual arrow so the diff is scannable. Empty values render as `null`.
  const columns: Column<AdminAuditLog>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (a) => <strong>#{a.id}</strong> },
    {
      key: 'when', header: t('col.when'), width: '160px',
      cell: (a) => <span className="muted">{a.created_at?.slice(0, 19).replace('T', ' ')}</span>,
    },
    {
      key: 'user', header: t('col.subject'), width: '110px',
      cell: (a) => <span>user #{a.user_id}</span>,
    },
    {
      key: 'field', header: t('col.field'),
      cell: (a) => <code style={{ background: 'transparent', padding: 0 }}>{a.changed_field}</code>,
    },
    {
      key: 'diff', header: t('col.change'),
      cell: (a) => (
        <div className="audit-diff">
          <span className="audit-old">{a.old_value ?? <em className="muted">null</em>}</span>
          <span className="audit-arrow">→</span>
          <span className="audit-new">{a.new_value ?? <em className="muted">null</em>}</span>
        </div>
      ),
    },
    {
      key: 'actor', header: t('col.actor'), width: '140px',
      cell: (a) => (
        <div className="cell-stack">
          <span className={`badge ${actorClass(a.actor_source)}`}>{a.actor_source}</span>
          {a.actor_user_id && <span className="muted">#{a.actor_user_id}</span>}
        </div>
      ),
    },
    {
      key: 'meta', header: '', width: '36px',
      cell: (a) =>
        a.metadata_json ? (
          <button className="row-edit-btn" onClick={() => setExpanded(expanded === a.id ? null : a.id)}>
            {expanded === a.id ? '−' : '+'}
          </button>
        ) : null,
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.audit.title')}</h1>
          <p className="muted">{t('page.audit.description')}</p>
        </div>
        <div className="row">
          <input
            type="number"
            min={1}
            value={userIDFilter}
            onChange={(e) => { setUserIDFilter(e.target.value); setPage(1) }}
            placeholder="user_id"
            style={{ width: '120px' }}
          />
          <select value={field} onChange={(e) => { setField(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            <option value="">{t('filter.all_fields')}</option>
            {fields.map(f => <option key={f} value={f}>{f}</option>)}
          </select>
          <select value={actor} onChange={(e) => setActor(e.target.value)} style={{ width: 'auto' }}>
            <option value="">{t('filter.all_actors')}</option>
            {actors.map(a => <option key={a} value={a}>{a}</option>)}
          </select>
          <button className="secondary" onClick={exportCsv}>{t('common.export_csv')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<AdminAuditLog> rows={items} columns={columns} rowKey={(a) => a.id} loading={loading} empty={t('empty.audit')} />
      {expanded !== null && (() => {
        const row = items.find((a) => a.id === expanded)
        if (!row || !row.metadata_json) return null
        let pretty: string
        try { pretty = JSON.stringify(JSON.parse(row.metadata_json), null, 2) }
        catch { pretty = row.metadata_json }
        return (
          <pre className="audit-meta-panel">
            <strong>metadata for #{row.id}</strong>{'\n'}{pretty}
          </pre>
        )
      })()}
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
    </div>
  )
}
