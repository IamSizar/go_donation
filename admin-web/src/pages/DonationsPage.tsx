import { useCallback, useEffect, useState, useRef } from 'react'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import {
  paymentStatusLabel,
  type DonationAdminRow,
  type DonationsListResp,
} from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'
import { downloadCsv, type CsvColumn } from '../lib/csv'
import { HighlightBanner, useHighlightedRow } from '../lib/useHighlightedRow'
import { stripeForDonation } from '../lib/statusColors'
import { formatPhone } from '../lib/phone'

const DONATION_CSV_COLUMNS: CsvColumn<DonationAdminRow>[] = [
  { header: 'id', get: (d) => d.id },
  { header: 'reference_number', get: (d) => d.reference_number },
  { header: 'user_id', get: (d) => d.user_id },
  { header: 'donor_full_name', get: (d) => d.donor_full_name },
  { header: 'donor_phone', get: (d) => d.donor_phone },
  { header: 'campaign_id', get: (d) => d.campaign_id },
  { header: 'campaign_title', get: (d) => d.campaign_title },
  { header: 'amount', get: (d) => d.amount },
  { header: 'currency', get: (d) => d.currency },
  { header: 'payment_status', get: (d) => paymentStatusLabel(d.payment_status) },
  { header: 'delivery_status', get: (d) => d.delivery_status },
  { header: 'payment_method', get: (d) => d.payment_method },
  { header: 'transaction_date', get: (d) => d.transaction_date },
]

const PER_PAGE = 20

const PAYMENT_LABELS = ['success', 'pending', 'failed']
const DELIVERY_STATUSES = ['registered', 'received', 'under_review', 'delivered', 'paused', 'archived', 'cancelled']

function paymentLabelToCode(label: string): number {
  if (label === 'success') return 1
  if (label === 'pending') return 2
  if (label === 'failed') return 3
  return 0
}

const DONATION_KINDS = ['general', 'campaign', 'sponsorship', 'in_kind', 'operational']

const DONATION_FIELDS: FieldSpec[] = [
  { key: 'reference_number', label: 'Reference #', labelKey: 'field.reference',    type: 'text' },
  { key: 'amount',           label: 'Amount', labelKey: 'field.amount',         type: 'text', required: true },
  { key: 'payment_method',   label: 'Payment method', labelKey: 'field.payment_method', type: 'text', required: true },
  { key: 'payment_status',   label: 'Payment', labelKey: 'field.payment',        type: 'select', options: PAYMENT_LABELS },
  { key: 'delivery_status',  label: 'Delivery', labelKey: 'field.delivery',       type: 'select', options: DELIVERY_STATUSES },
  { key: 'message',          label: 'Message', labelKey: 'field.message',        type: 'textarea', rows: 3, required: true },
  { key: 'impact_note',      label: 'Impact note', labelKey: 'field.impact_note',    type: 'textarea', rows: 3 },
]

const DONATION_CREATE_FIELDS: FieldSpec[] = [
  { key: 'user_id',       label: 'Contributor user ID', labelKey: 'field.donor_user_id',     type: 'number', required: true },
  { key: 'campaign_id',   label: 'Campaign ID', labelKey: 'field.campaign_id',       type: 'number' },
  { key: 'donation_kind', label: 'Kind', labelKey: 'field.kind',              type: 'select', options: DONATION_KINDS },
  ...DONATION_FIELDS,
]

function formatAmount(s: string): string {
  const n = parseFloat(s)
  if (!isFinite(n)) return s
  return n.toLocaleString()
}

function formatDate(iso: string): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return iso
  return d.toLocaleString()
}

export default function DonationsPage() {
  const [page, setPage] = useState(1)
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<DonationsListResp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<DonationAdminRow | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<DonationAdminRow | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t } = useI18n()
  // Live-feed click landing: scrolls to and pulses the matching row when the
  // URL has `?highlight=<id>`. No-op for direct visits to /donations.
  const highlight = useHighlightedRow()

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<DonationsListResp>('/api/admin/donations', { params: { page, per_page: PER_PAGE, q: q || undefined } })
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
  }, [page, q, refreshTick])

  // Phase 27 / 27.9 — live refresh every 5s while the tab is visible.
  // Setting pollSilent before bumping refreshTick reuses the same fetch
  // but keeps the loading flag off, so the list updates in place with no
  // spinner flash. Critical surface — donor confirmations surface fast.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  // payment_status is a label in the form; convert to int for the backend.
  const remapPayment = (p: Record<string, unknown>): Record<string, unknown> => {
    const out = { ...p }
    if (typeof out.payment_status === 'string') {
      out.payment_status = paymentLabelToCode(out.payment_status as string)
    }
    return out
  }

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/donations/${id}`, remapPayment(patch))
      toast.success(t('toast.saved', { noun: `${t('noun.donation')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/donations`, remapPayment(data))
      toast.success(t('toast.created', { noun: `${t('noun.donation')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`donations-${new Date().toISOString().slice(0, 10)}.csv`, rows, DONATION_CSV_COLUMNS)
  }

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/donations/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.donation')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  // Pre-shape the row passed into the modal: payment_status is a number on the
  // row, but the form uses the label.
  function rowForEdit(d: DonationAdminRow): Record<string, unknown> {
    return { ...d, payment_status: paymentStatusLabel(d.payment_status) }
  }

  const columns: Column<DonationAdminRow>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (d) => <strong>#{d.id}</strong> },
    {
      key: 'ref',
      header: t('col.reference'),
      cell: (d) =>
        d.reference_number ? (
          <code style={{ background: 'transparent', padding: 0 }}>{d.reference_number}</code>
        ) : (
          <span className="muted">—</span>
        ),
    },
    {
      key: 'donor',
      header: t('col.donor'),
      cell: (d) => (
        <div className="cell-stack">
          <strong>{d.donor_full_name ?? `#${d.user_id}`}</strong>
          <span className="muted">{formatPhone(d.donor_phone)}</span>
        </div>
      ),
    },
    {
      key: 'campaign',
      header: t('col.campaign'),
      cell: (d) =>
        d.campaign_title ? (
          d.campaign_title
        ) : (
          <span className="muted">—</span>
        ),
    },
    {
      key: 'amount',
      header: t('col.amount'),
      align: 'right',
      cell: (d) => (
        <strong>
          {formatAmount(d.amount)} <span className="muted">{d.currency}</span>
        </strong>
      ),
    },
    {
      key: 'status',
      header: t('col.payment'),
      cell: (d) => (
        <StatusCell
          value={paymentStatusLabel(d.payment_status)}
          allowed={PAYMENT_LABELS}
          onSave={(next) =>
            api.post(`/api/admin/donations/${d.id}/status`, { payment_status: paymentLabelToCode(next) })
          }
          label={`Donation #${d.id} payment`}
        />
      ),
    },
    {
      key: 'delivery',
      header: t('col.delivery'),
      cell: (d) => (
        <StatusCell
          value={d.delivery_status ?? 'registered'}
          allowed={DELIVERY_STATUSES}
          onSave={(next) =>
            api.post(`/api/admin/donations/${d.id}/status`, { delivery_status: next })
          }
          label={`Donation #${d.id} delivery`}
        />
      ),
    },
    { key: 'method', header: t('col.method'), cell: (d) => d.payment_method || <span className="muted">—</span> },
    {
      key: 'date',
      header: t('col.date'),
      cell: (d) => <span className="muted">{formatDate(d.transaction_date)}</span>,
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (d) => (
        <>
          <Link className="row-edit-btn" to={`/detail/donations/${d.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(d)}>{t('common.edit')}</button>
          <button className="row-delete-btn" onClick={() => setDeleting(d)}>{t('common.delete')}</button>
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.donations.title')}</h1>
          <p className="muted">{resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}</p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1) }}
            placeholder={t('page.donations.search_placeholder')}
            style={{ width: '220px' }}
          />
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.donations.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      {/* Banner appears only when the URL has `?highlight=<id>` (set by the
          dashboard live-feed click). Tells the admin which row they jumped
          to and offers a dismiss. */}
      <HighlightBanner kind={t('noun.donation')} />
      <Table<DonationAdminRow>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(d) => d.id}
        loading={loading}
        empty={t('empty.donations')}
        rowProps={(d) => ({
          // is-highlighted triggers the emerald pulse via index.css;
          // data-highlight-id is the anchor useHighlightedRow scrolls to;
          // row-stripe-* draws the 4px coloured bar on the left edge.
          className: [
            highlight.isHighlighted(d.id) ? 'is-highlighted' : '',
            stripeForDonation({
              delivery_status: d.delivery_status,
              payment_status: d.payment_status,
            }),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(d.id),
        })}
      />
      <Pagination
        page={page}
        totalPages={resp?.total_pages ?? 1}
        onPageChange={setPage}
        disabled={loading}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.donation') }) : editing ? t('common.modal_edit', { noun: t('noun.donation'), id: editing.id }) : ''}
        initial={creating ? {} : editing ? rowForEdit(editing) : {}}
        fields={creating ? DONATION_CREATE_FIELDS : DONATION_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.donation'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body_noun', { noun: t('noun.donation') }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
