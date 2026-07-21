import { useCallback, useEffect, useState, useRef } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
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
import { type CsvColumn } from '../lib/csv'
import { HighlightBanner, useHighlightedRow } from '../lib/useHighlightedRow'
import { stripeForDonation } from '../lib/statusColors'
import { formatDateParts } from '../lib/dates'

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
  { header: 'donation_type', get: (d) => d.donation_type },
  { header: 'transaction_date', get: (d) => d.transaction_date },
]

const PER_PAGE = 20

const PAYMENT_LABELS = ['success', 'pending', 'failed']
const DELIVERY_STATUSES = ['registered', 'received', 'under_review', 'delivered', 'suspended', 'paused', 'archived', 'cancelled']

function paymentLabelToCode(label: string): number {
  if (label === 'success') return 1
  if (label === 'pending') return 2
  if (label === 'failed') return 3
  return 0
}

const DONATION_KINDS = ['general', 'campaign', 'sponsorship', 'in_kind', 'operational']
const DONATION_TYPES = ['general', 'zakat', 'sadaqah']

const DONATION_FIELDS: FieldSpec[] = [
  { key: 'reference_number', label: 'Reference #', labelKey: 'field.reference',    type: 'text' },
  { key: 'amount',           label: 'Amount', labelKey: 'field.amount',         type: 'text', required: true },
  { key: 'payment_method',   label: 'Payment method', labelKey: 'field.payment_method', type: 'text', required: true },
  { key: 'payment_status',   label: 'Payment', labelKey: 'field.payment',        type: 'select', options: PAYMENT_LABELS },
  { key: 'delivery_status',  label: 'Delivery', labelKey: 'field.delivery',       type: 'select', options: DELIVERY_STATUSES },
  { key: 'donation_type',    label: 'Type', labelKey: 'field.donation_type',   type: 'select', options: DONATION_TYPES },
  { key: 'message',          label: 'Message', labelKey: 'field.message',        type: 'textarea', rows: 3, required: true },
  { key: 'impact_note',      label: 'Impact note', labelKey: 'field.impact_note',    type: 'textarea', rows: 3 },
]

const DONATION_CREATE_FIELDS: FieldSpec[] = [
  { key: 'user_id',       label: 'Grantor user ID', labelKey: 'field.donor_user_id',     type: 'number', required: true },
  { key: 'campaign_id',   label: 'Campaign ID', labelKey: 'field.campaign_id',       type: 'number' },
  { key: 'donation_kind', label: 'Kind', labelKey: 'field.kind',              type: 'select', options: DONATION_KINDS },
  ...DONATION_FIELDS,
]

function formatAmount(s: string): string {
  const n = parseFloat(s)
  if (!isFinite(n)) return s
  return n.toLocaleString()
}

// Note #14 — was one combined date+time string on a single line, wide enough
// to squeeze the columns after it. formatDateParts (lib/dates.ts, now also
// used by VolunteersPage per Note #20) splits it so the cell stacks
// vertically instead (reuses the .cell-stack class the Donor column already
// uses for the same reason).

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
    {
      // Note #14 — was a bare "#15"; the client wants an exported-document
      // style code instead of a raw hash. Display-only change: `d.id` itself
      // is still the plain auto-increment int underneath (used unchanged in
      // every API call/link/search on this page), just prefixed with "T"
      // (Tawazzun) instead of "#" for the on-screen/export representation.
      key: 'id', header: t('col.id'), width: '60px', cell: (d) => <strong>T{d.id}</strong>,
    },
    {
      key: 'ref',
      header: t('col.reference'),
      cell: (d) =>
        d.reference_number ? (
          // Note #14 — the full reference_number is kept intact (it's a real
          // search key and appears in the donor's own donation history, per
          // investigation — shortening the VALUE would break both). Only the
          // on-screen presentation is decluttered: truncated with an ellipsis
          // and the full code available via title-tooltip/selection.
          <code
            title={d.reference_number}
            style={{
              background: 'transparent', padding: 0, display: 'inline-block',
              maxWidth: '140px', overflow: 'hidden', textOverflow: 'ellipsis',
              whiteSpace: 'nowrap', verticalAlign: 'bottom', fontSize: '0.85em',
            }}
          >
            {d.reference_number}
          </code>
        ) : (
          <span className="muted">—</span>
        ),
    },
    {
      key: 'donor',
      header: t('col.donor'),
      cell: (d) => (
        // Note #14 — was name + phone (+ the adjacent date column reading as
        // a "year", per the client). Phone is already one click away on the
        // View page; showing the user's #id here instead keeps the row
        // scannable and lets an admin cross-reference the Users table.
        <div className="cell-stack">
          <strong>{d.donor_full_name ?? <span className="muted">—</span>}</strong>
          <span className="muted">#{d.user_id}</span>
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
          // Note #13 — 'paused' reads as a near-duplicate of 'suspended' in
          // this column's Arabic/Kurdish translations (both landed on some
          // variant of "temporarily halted"). Here specifically it means a
          // delivery currently being handled, so it displays as "Processing"
          // — without touching the shared status.paused label used by
          // Marriage/Sponsorships, where "Paused" correctly means on-hold.
          labelOverrides={{ paused: t('status.processing') }}
        />
      ),
    },
    { key: 'method', header: t('col.method'), cell: (d) => d.payment_method || <span className="muted">—</span> },
    { key: 'type', header: t('col.type'), cell: (d) => <span className="muted">{d.donation_type || '—'}</span> },
    {
      key: 'date',
      header: t('col.date'),
      cell: (d) => {
        const { date, time } = formatDateParts(d.transaction_date)
        return (
          <div className="cell-stack">
            <span className="muted">{date}</span>
            {time && <span className="muted" style={{ fontSize: '0.85em' }}>{time}</span>}
          </div>
        )
      },
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (d) => (
        <>
          <Link className="row-edit-btn" to={`/detail/donations/${d.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(d)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(d)} />
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
          <ExportCsvButton
            rows={resp?.items ?? []}
            columns={DONATION_CSV_COLUMNS}
            filenameBase="donations"
            title={t('nav.donations')}
            module="donations"
          />
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
