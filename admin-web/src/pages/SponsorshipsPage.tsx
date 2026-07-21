import { useCallback, useEffect, useState, useRef } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { Sponsorship, SponsorshipsListResp } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import BulkBar from '../components/BulkBar'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { type CsvColumn } from '../lib/csv'
import { HighlightBanner, useHighlightedRow } from '../lib/useHighlightedRow'
import { stripeForStatus } from '../lib/statusColors'
import { formatDateParts } from '../lib/dates'

const SPONSORSHIP_CSV_COLUMNS: CsvColumn<Sponsorship>[] = [
  { header: 'id', get: (s) => sponsorshipCode(s.id) },
  { header: 'donor_user_id', get: (s) => s.donor_user_id },
  { header: 'donor_full_name', get: (s) => s.donor_full_name },
  { header: 'donor_phone', get: (s) => s.donor_phone },
  { header: 'project_title', get: (s) => s.project_title },
  { header: 'sponsorship_type', get: (s) => s.sponsorship_type },
  { header: 'amount', get: (s) => s.amount },
  { header: 'currency', get: (s) => s.currency },
  { header: 'schedule_interval', get: (s) => s.schedule_interval },
  { header: 'next_due_date', get: (s) => s.next_due_date },
  { header: 'status', get: (s) => s.status },
  { header: 'created_at', get: (s) => s.created_at },
]

const SPONSORSHIP_STATUSES = ['pending', 'active', 'paused', 'delayed', 'stopped', 'completed', 'cancelled']
const SCHEDULE_INTERVALS = ['weekly', 'monthly', 'quarterly', 'yearly']

const SPONSORSHIP_FIELDS: FieldSpec[] = [
  { key: 'sponsorship_type',  label: 'Type', labelKey: 'field.type',              type: 'text',     required: true },
  { key: 'amount',            label: 'Amount', labelKey: 'field.amount',            type: 'number' },
  { key: 'currency',          label: 'Currency', labelKey: 'field.currency',          type: 'text',     placeholder: 'IQD' },
  { key: 'schedule_interval', label: 'Schedule', labelKey: 'field.schedule',          type: 'select',   options: SCHEDULE_INTERVALS },
  { key: 'next_due_date',     label: 'Next due date', labelKey: 'field.next_due_date',     type: 'text',     placeholder: 'YYYY-MM-DD' },
  { key: 'status',            label: 'Status', labelKey: 'field.status',            type: 'select',   options: SPONSORSHIP_STATUSES },
  { key: 'notes',             label: 'Notes', labelKey: 'field.notes',             type: 'textarea', rows: 3 },
]

const SPONSORSHIP_CREATE_FIELDS: FieldSpec[] = [
  { key: 'donor_user_id', label: 'Grantor user ID (optional)', labelKey: 'field.donor_user_id_optional', type: 'number' },
  ...SPONSORSHIP_FIELDS,
]

function formatAmount(s: string): string {
  const n = parseFloat(s)
  if (!isFinite(n)) return s
  return n.toLocaleString()
}

function formatDate(iso: string | null): string {
  if (!iso) return '—'
  // backend stores DATE values; trim to YYYY-MM-DD when possible
  return iso.length >= 10 ? iso.slice(0, 10) : iso
}

// Replace the raw "#42" id with the app-wide "T{id}" code used everywhere
// else (Volunteers, Donations, Orders) instead of a section-specific prefix.
function sponsorshipCode(id: number): string {
  return `T${id}`
}

export default function SponsorshipsPage() {
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<SponsorshipsListResp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [statusFilter, setStatusFilter] = useState<string>('all')
  const [editing, setEditing] = useState<Sponsorship | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<Sponsorship | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<Sponsorship>((s) => s.id)
  // Pulses + scrolls to the sponsorship referenced by ?highlight=<id>.
  const highlight = useHighlightedRow()

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<SponsorshipsListResp>('/api/sponsorships', { params: { limit: 200, q: q || undefined } })
      .then((res) => {
        if (!cancelled) setResp(res.data)
      })
      .catch((e) => {
        if (!cancelled && !pollSilent.current) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled && !pollSilent.current) setLoading(false)
        pollSilent.current = false
      })
    return () => {
      cancelled = true
    }
  }, [q, refreshTick])

  // Phase 27 — live refresh sponsorships every 10s. Slower-moving than
  // donations; mostly admin watching for new requests.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 10_000)

  const trimDate = (p: Record<string, unknown>) => {
    const out = { ...p }
    if (typeof out.next_due_date === 'string' && out.next_due_date.length > 10) {
      out.next_due_date = out.next_due_date.slice(0, 10)
    }
    return out
  }

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/sponsorships/${id}`, trimDate(patch))
      toast.success(t('toast.saved', { noun: `${t('noun.sponsorship')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/sponsorships`, trimDate(data))
      toast.success(t('toast.created', { noun: `${t('noun.sponsorship')} #${res.data.id}` }))
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
        ids.map((id) => api.post(`/api/admin/sponsorships/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/sponsorships/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/sponsorships/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.sponsorship')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )


  const all = resp?.items ?? []
  const visible =
    statusFilter === 'all' ? all : all.filter((s) => s.status === statusFilter)
  const statusOptions = Array.from(new Set(all.map((s) => s.status))).sort()

  const columns: Column<Sponsorship>[] = [
    {
      key: 'id',
      header: t('col.id'),
      width: '70px',
      cell: (s) => <code style={{ background: 'transparent', padding: 0 }}>{sponsorshipCode(s.id)}</code>,
    },
    {
      key: 'donor',
      header: t('col.donor'),
      cell: (s) =>
        s.donor_user_id ? (
          <span>{s.donor_full_name ?? t('common.user_ref_lc', { id: s.donor_user_id })}</span>
        ) : (
          <span className="muted">—</span>
        ),
    },
    {
      key: 'target',
      header: t('col.target'),
      cell: (s) => (
        <div className="cell-stack">
          <strong>{s.project_title}</strong>
          <span className="muted">{statusLabel(s.sponsorship_type)}</span>
        </div>
      ),
    },
    {
      key: 'amount',
      header: t('col.amount'),
      align: 'right',
      cell: (s) => (
        <strong>
          {formatAmount(s.amount)} <span className="muted">{s.currency}</span>
        </strong>
      ),
    },
    {
      key: 'schedule',
      header: t('col.schedule'),
      cell: (s) => <span className="muted">{statusLabel(s.schedule_interval)}</span>,
    },
    {
      key: 'next',
      header: t('col.next_due'),
      cell: (s) => <span className="muted">{formatDate(s.next_due_date)}</span>,
    },
    {
      key: 'created',
      header: t('col.created'),
      cell: (s) => {
        const { date, time } = formatDateParts(s.created_at)
        return (
          <div className="cell-stack">
            <span>{date}</span>
            {time && <span className="muted">{time}</span>}
          </div>
        )
      },
    },
    {
      key: 'status',
      header: t('col.status'),
      cell: (s) => (
        <StatusCell
          value={s.status}
          allowed={SPONSORSHIP_STATUSES}
          onSave={(next) => api.post(`/api/admin/sponsorships/${s.id}/status`, { status: next })}
          label={t('common.status')}
        />
      ),
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (s) => (
        <>
          <Link className="row-edit-btn" to={`/detail/sponsorships/${s.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(s)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(s)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.sponsorships.title')}</h1>
          <p className="muted">
            {loading
              ? t('common.loading')
              : `${visible.length} ${t('common.of')} ${all.length} ${t('common.shown')}`}
          </p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); sel.clear() }}
            placeholder={t('page.sponsorships.search_placeholder')}
            style={{ width: '200px' }}
          />
          <select
            value={statusFilter}
            onChange={(e) => { setStatusFilter(e.target.value); sel.clear() }}
            style={{ width: 'auto' }}
          >
            <option value="all">{t('filter.all_statuses')}</option>
            {statusOptions.map((s) => (
              <option key={s} value={s}>
                {statusLabel(s)}
              </option>
            ))}
          </select>
          <ExportCsvButton
            rows={visible}
            columns={SPONSORSHIP_CSV_COLUMNS}
            filenameBase="sponsorships"
            title={t('nav.sponsorships')}
            module="sponsorships"
          />
          <button onClick={() => setCreating(true)}>{t('page.sponsorships.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.sponsorship')} />
      <Table<Sponsorship>
        rows={visible}
        columns={columns}
        rowKey={(s) => s.id}
        loading={loading}
        empty={t('empty.sponsorships')}
        rowProps={(s) => ({
          className: [
            highlight.isHighlighted(s.id) ? 'is-highlighted' : '',
            stripeForStatus(s.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(s.id),
        })}
        selectable={sel.forRows(visible)}
      />
      <BulkBar
        count={sel.count}
        allowed={SPONSORSHIP_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun={t('noun.sponsorship')}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.sponsorship'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body_noun', { noun: t('noun.sponsorship') }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.sponsorship') }) : editing ? t('common.modal_edit', { noun: t('noun.sponsorship'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={creating ? SPONSORSHIP_CREATE_FIELDS : SPONSORSHIP_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}
