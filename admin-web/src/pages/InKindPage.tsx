import { useCallback, useEffect, useState, useRef } from 'react'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { AdminPageResp, AdminInKind } from '../lib/api-types'
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

const INKIND_CSV_COLUMNS: CsvColumn<AdminInKind>[] = [
  { header: 'id', get: (k) => k.id },
  { header: 'donor_user_id', get: (k) => k.donor_user_id },
  { header: 'donor_full_name', get: (k) => k.donor_full_name },
  { header: 'donor_phone', get: (k) => k.donor_phone },
  { header: 'category', get: (k) => k.category },
  { header: 'item_name', get: (k) => k.item_name },
  { header: 'quantity', get: (k) => k.quantity },
  { header: 'status', get: (k) => k.status },
  { header: 'created_at', get: (k) => k.created_at },
]

const PER_PAGE = 20

const STATUSES = ['all', 'submitted', 'scheduled', 'received', 'delivered', 'cancelled']
const EDITABLE_STATUSES = STATUSES.filter((s) => s !== 'all')

const INKIND_FIELDS: FieldSpec[] = [
  { key: 'category',       label: 'Category', labelKey: 'field.category',       type: 'text', required: true },
  { key: 'item_name',      label: 'Item', labelKey: 'field.item',           type: 'text', required: true },
  { key: 'quantity',       label: 'Quantity', labelKey: 'field.quantity',       type: 'text' },
  { key: 'condition_note', label: 'Condition', labelKey: 'field.condition',      type: 'text' },
  { key: 'status',         label: 'Status', labelKey: 'field.status',         type: 'select', options: EDITABLE_STATUSES },
  { key: 'pickup_address', label: 'Pickup address', labelKey: 'field.pickup_address', type: 'textarea', rows: 2 },
  { key: 'notes',          label: 'Notes', labelKey: 'field.notes',          type: 'textarea', rows: 3 },
]

const INKIND_CREATE_FIELDS: FieldSpec[] = [
  { key: 'donor_user_id', label: 'Contributor user ID (optional)', labelKey: 'field.donor_user_id_optional', type: 'number' },
  ...INKIND_FIELDS,
]

export default function InKindPage() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminInKind> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<AdminInKind | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<AdminInKind | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<AdminInKind>((k) => k.id)
  const highlight = useHighlightedRow()

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<AdminInKind>>('/api/admin/in_kind_donations', {
        params: { page, per_page: PER_PAGE, status, q: q || undefined },
      })
      .then(r => { if (!cancelled) setResp(r.data) })
      .catch(e => { if (!cancelled && !pollSilent.current) setErr(describeError(e)) })
      .finally(() => { if (!cancelled && !pollSilent.current) setLoading(false); pollSilent.current = false })
    return () => { cancelled = true }
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh in-kind donations every 10s.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 10_000)

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/in_kind_donations/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.in_kind_donation')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/in_kind_donations`, data)
      toast.success(t('toast.created', { noun: `${t('noun.in_kind_donation')} #${res.data.id}` }))
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
        ids.map((id) => api.post(`/api/admin/in_kind_donations/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/in_kind_donations/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/in_kind_donations/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.in_kind_donation')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`inkind-${new Date().toISOString().slice(0, 10)}.csv`, rows, INKIND_CSV_COLUMNS)
  }

  const columns: Column<AdminInKind>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (k) => <strong>#{k.id}</strong> },
    {
      key: 'donor', header: t('col.donor'),
      cell: (k) => (
        <div className="cell-stack">
          <strong>{k.donor_full_name ?? (k.donor_user_id ? `user #${k.donor_user_id}` : '—')}</strong>
          {k.donor_phone && <span className="muted">{k.donor_phone}</span>}
        </div>
      ),
    },
    { key: 'cat', header: t('col.category'), cell: (k) => k.category },
    { key: 'item', header: t('col.item'), cell: (k) => k.item_name },
    { key: 'qty', header: t('col.quantity'), cell: (k) => k.quantity ?? <span className="muted">—</span> },
    { key: 'pickup', header: t('col.pickup'), cell: (k) => k.pickup_address ?? <span className="muted">—</span> },
    {
      key: 'status', header: t('col.status'),
      cell: (k) => (
        <StatusCell
          value={k.status}
          allowed={STATUSES.filter((s) => s !== 'all')}
          onSave={(next) => api.post(`/api/admin/in_kind_donations/${k.id}/status`, { status: next })}
          label={`In-kind #${k.id}`}
        />
      ),
    },
    { key: 'created', header: t('col.created'), cell: (k) => <span className="muted">{k.created_at?.slice(0, 10)}</span> },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (k) => (
        <>
          <Link className="row-edit-btn" to={`/detail/in_kind_donations/${k.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(k)}>{t('common.edit')}</button>
          <button className="row-delete-btn" onClick={() => setDeleting(k)}>{t('common.delete')}</button>
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.in_kind.title')}</h1>
          <p className="muted">{resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}</p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.in_kind.search_placeholder')}
            style={{ width: '200px' }}
          />
          <select value={status} onChange={e => { setStatus(e.target.value); setPage(1); sel.clear() }} style={{ width: 'auto' }}>
            {STATUSES.map(s => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.in_kind.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.in_kind_donation')} />
      <Table<AdminInKind>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(k) => k.id}
        loading={loading}
        empty={t('empty.in_kind')}
        selectable={sel.forRows(resp?.items ?? [])}
        rowProps={(k) => ({
          className: [
            highlight.isHighlighted(k.id) ? 'is-highlighted' : '',
            stripeForStatus(k.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(k.id),
        })}
      />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="donations"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.in_kind_donation'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body', { name: deleting.item_name }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.in_kind_donation') }) : editing ? t('common.modal_edit', { noun: t('noun.in_kind_donation'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={creating ? INKIND_CREATE_FIELDS : INKIND_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}
