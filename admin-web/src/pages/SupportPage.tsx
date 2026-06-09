import { useCallback, useEffect, useState, useRef } from 'react'
import { Link } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { AdminPageResp, AdminTicket } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import BulkBar from '../components/BulkBar'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { downloadCsv, type CsvColumn } from '../lib/csv'
import { HighlightBanner, useHighlightedRow } from '../lib/useHighlightedRow'
import { stripeForStatus } from '../lib/statusColors'

const TICKET_CSV_COLUMNS: CsvColumn<AdminTicket>[] = [
  { header: 'id', get: (t) => t.id },
  { header: 'user_id', get: (t) => t.user_id },
  { header: 'user_full_name', get: (t) => t.user_full_name },
  { header: 'user_phone', get: (t) => t.user_phone },
  { header: 'subject', get: (t) => t.subject },
  { header: 'message', get: (t) => t.message },
  { header: 'status', get: (t) => t.status },
  { header: 'created_at', get: (t) => t.created_at },
]

const PER_PAGE = 20

const STATUSES = ['all', 'open', 'in_progress', 'resolved', 'closed']
const EDITABLE_STATUSES = STATUSES.filter((s) => s !== 'all')

const TICKET_FIELDS: FieldSpec[] = [
  { key: 'subject', label: 'Subject', labelKey: 'field.subject', type: 'text', required: true },
  { key: 'status',  label: 'Status', labelKey: 'field.status',  type: 'select', options: EDITABLE_STATUSES },
  { key: 'message', label: 'Message', labelKey: 'field.message', type: 'textarea', rows: 6, required: true },
]

const TICKET_CREATE_FIELDS: FieldSpec[] = [
  { key: 'user_id', label: 'User ID (optional)', labelKey: 'field.user_id_optional', type: 'number' },
  ...TICKET_FIELDS,
]

export default function SupportPage() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminTicket> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [open, setOpen] = useState<number | null>(null)
  const [editing, setEditing] = useState<AdminTicket | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<AdminTicket | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t: tr } = useI18n()
  const statusLabel = useStatusLabel()
  // Pulses + scrolls to the ticket referenced by ?highlight=<id>.
  const highlight = useHighlightedRow()
  const sel = useSelection<AdminTicket>((t) => t.id)

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<AdminTicket>>('/api/admin/support_tickets', {
        params: { page, per_page: PER_PAGE, status, q: q || undefined },
      })
      .then(r => { if (!cancelled) setResp(r.data) })
      .catch(e => { if (!cancelled && !pollSilent.current) setErr(describeError(e)) })
      .finally(() => { if (!cancelled && !pollSilent.current) setLoading(false); pollSilent.current = false })
    return () => { cancelled = true }
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh every 5s. Support tickets are time-sensitive
  // (donor / volunteer waiting for a reply), so the same fast cadence
  // as donations applies here.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/support_tickets/${id}`, patch)
      toast.success(tr('toast.saved', { noun: `${tr('noun.support_ticket')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/support_tickets`, data)
      toast.success(tr('toast.created', { noun: `${tr('noun.support_ticket')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const applyBulkStatus = useCallback(
    async (newStatus: string) => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.post(`/api/admin/support_tickets/${id}/status`, { status: newStatus })),
      )
      const ok = results.filter((r) => r.status === 'fulfilled').length
      sel.clear()
      setRefreshTick((t) => t + 1)
      return { ok, fail: results.length - ok }
    },
    [sel],
  )

  const applyBulkDelete = useCallback(async () => {
    const ids = [...sel.selected]
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/support_tickets/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/support_tickets/${id}`)
      toast.success(tr('toast.deleted', { noun: `${tr('noun.support_ticket')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(tr('common.nothing_to_export')); return }
    downloadCsv(`tickets-${new Date().toISOString().slice(0, 10)}.csv`, rows, TICKET_CSV_COLUMNS)
  }

  const columns: Column<AdminTicket>[] = [
    { key: 'id', header: tr('col.id'), width: '60px', cell: (t) => <strong>#{t.id}</strong> },
    {
      key: 'user', header: tr('col.user'),
      cell: (t) => (
        <div className="cell-stack">
          <strong>{t.user_full_name ?? (t.user_id ? `user #${t.user_id}` : '—')}</strong>
          {t.user_phone && <span className="muted">{t.user_phone}</span>}
        </div>
      ),
    },
    { key: 'subject', header: tr('col.subject'), cell: (t) => <strong>{t.subject}</strong> },
    {
      key: 'message', header: tr('col.message'),
      cell: (t) =>
        open === t.id ? (
          <span>{t.message}</span>
        ) : (
          <a href="#" onClick={(e) => { e.preventDefault(); setOpen(t.id) }}>
            {t.message.slice(0, 80)}{t.message.length > 80 ? '…' : ''}
          </a>
        ),
    },
    {
      key: 'status', header: tr('col.status'),
      cell: (t) => (
        <StatusCell
          value={t.status}
          allowed={STATUSES.filter((s) => s !== 'all')}
          onSave={(next) => api.post(`/api/admin/support_tickets/${t.id}/status`, { status: next })}
          label={`Ticket #${t.id}`}
        />
      ),
    },
    { key: 'created', header: tr('col.created'), cell: (t) => <span className="muted">{t.created_at?.slice(0, 10)}</span> },
    {
      key: 'actions', header: '', width: '170px',
      cell: (t) => (
        <>
          <Link className="row-edit-btn" to={`/detail/support_tickets/${t.id}`}>{tr('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(t)}>{tr('common.edit')}</button>
          <button className="row-delete-btn" onClick={() => setDeleting(t)}>{tr('common.delete')}</button>
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{tr('page.support.title')}</h1>
          <p className="muted">{resp ? `${resp.total_items} ${tr('common.total')}` : tr('common.loading')}</p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={tr('page.support.search_placeholder')}
            style={{ width: '220px' }}
          />
          <select value={status} onChange={e => { setStatus(e.target.value); setPage(1); sel.clear() }} style={{ width: 'auto' }}>
            {STATUSES.map(s => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <button className="secondary" onClick={exportCsv}>{tr('common.export_csv')}</button>
          <button onClick={() => setCreating(true)}>{tr('page.support.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={tr('noun.support_ticket')} />
      <Table<AdminTicket>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(t) => t.id}
        loading={loading}
        empty={tr('empty.support')}
        selectable={sel.forRows(resp?.items ?? [])}
        rowProps={(t) => ({
          className: [
            highlight.isHighlighted(t.id) ? 'is-highlighted' : '',
            stripeForStatus(t.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(t.id),
        })}
      />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="tickets"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? tr('common.confirm_delete_title', { noun: tr('noun.support_ticket'), id: deleting.id }) : ''}
        message={deleting ? tr('common.confirm_delete_body', { name: deleting.subject }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? tr('common.modal_new', { noun: tr('noun.support_ticket') }) : editing ? tr('common.modal_edit', { noun: tr('noun.support_ticket'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={creating ? TICKET_CREATE_FIELDS : TICKET_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}
