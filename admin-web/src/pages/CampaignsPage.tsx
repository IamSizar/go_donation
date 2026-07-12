// CampaignsPage — Phase 14 admin view of the real `campaigns` table.
//
// Note: the legacy /api/campaigns endpoint (mobile-facing) projects rows
// from `beneficiary_project_requests`. This page reads from /api/admin/campaigns
// which targets the real `campaigns` table — that's why a campaign here
// has no status, category, or like/comment counts: those don't exist on
// the underlying table.

import { useCallback, useEffect, useState } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import ExportCsvButton from '../components/ExportCsvButton'
import { Link } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import type { AdminCampaign, AdminPageResp, CampaignStatus } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { type CsvColumn } from '../lib/csv'

const PER_PAGE = 12

// Phase 15.1 — Campaign lifecycle status. The select in the EditModal stores
// values as strings; we expose three human labels that map to the backend's
// 'active' / 'hidden' / 'finished' enum-style column.
const STATUS_ACTIVE_LABEL   = 'Active — accepting donations'
const STATUS_HIDDEN_LABEL   = 'Hidden — not visible to donors'
const STATUS_FINISHED_LABEL = 'Finished — closed for donations'

// Display metadata for the column badge. Tone names match the existing
// `.badge.tone-…` styles in index.css.
const STATUS_BADGES: Record<CampaignStatus, { label: string; tone: 'success' | 'warning' | 'info' }> = {
  active:   { label: 'Active',   tone: 'success' },
  hidden:   { label: 'Hidden',   tone: 'warning' },
  finished: { label: 'Finished', tone: 'info' },
}

const CAMPAIGN_FIELDS: FieldSpec[] = [
  {
    key: 'status',
    label: 'Lifecycle status', labelKey: 'field.lifecycle_status',
    type: 'select',
    options: [STATUS_ACTIVE_LABEL, STATUS_HIDDEN_LABEL, STATUS_FINISHED_LABEL],
    required: true,
  },
  { key: 'title',              label: 'Title (EN)', labelKey: 'field.title_en',          type: 'text',     required: true },
  { key: 'title_ar',           label: 'Title (AR)', labelKey: 'field.title_ar',          type: 'text',     required: true, dir: 'rtl' },
  { key: 'title_sorani',       label: 'Title (Sorani)', labelKey: 'field.title_sorani',      type: 'text',     dir: 'rtl' },
  { key: 'title_badini',       label: 'Title (Badini)', labelKey: 'field.title_badini',      type: 'text',     dir: 'rtl' },
  { key: 'address',            label: 'Address', labelKey: 'field.address',             type: 'text',     required: true },
  { key: 'beneficiaries',      label: 'Eligibles', labelKey: 'field.beneficiaries',       type: 'text',     required: true, placeholder: 'e.g. 50 families' },
  { key: 'goal_amount',        label: 'Goal amount', labelKey: 'field.goal_amount',         type: 'text',     required: true, placeholder: 'IQD' },
  { key: 'raised_amount',      label: 'Raised amount', labelKey: 'field.raised_amount',       type: 'text',     placeholder: '0' },
  { key: 'description',        label: 'Description (EN)', labelKey: 'field.description_en',    type: 'textarea', rows: 4, required: true },
  { key: 'description_ar',     label: 'Description (AR)', labelKey: 'field.description_ar',    type: 'textarea', rows: 4, required: true, dir: 'rtl' },
  { key: 'description_sorani', label: 'Description (Sorani)', labelKey: 'field.description_sorani',type: 'textarea', rows: 4, dir: 'rtl' },
  { key: 'description_badini', label: 'Description (Badini)', labelKey: 'field.description_badini',type: 'textarea', rows: 4, dir: 'rtl' },
]

// Translate between the backend enum and the human label shown in the select.
function statusToLabel(s: CampaignStatus | string | undefined | null): string {
  switch (s) {
    case 'hidden':   return STATUS_HIDDEN_LABEL
    case 'finished': return STATUS_FINISHED_LABEL
    default:         return STATUS_ACTIVE_LABEL
  }
}
function labelToStatus(label: unknown): CampaignStatus {
  switch (label) {
    case STATUS_HIDDEN_LABEL:   return 'hidden'
    case STATUS_FINISHED_LABEL: return 'finished'
    default:                    return 'active'
  }
}

// Replace the modal's `status` label with the enum value the API wants.
// Called inside the create + edit save paths so the rest of the page stays
// unaware of the wire format.
function normalizeCampaignPatch(patch: Record<string, unknown>): Record<string, unknown> {
  if ('status' in patch) {
    return { ...patch, status: labelToStatus(patch.status) }
  }
  return patch
}

const CSV_COLUMNS: CsvColumn<AdminCampaign>[] = [
  { header: 'id', get: (c) => c.id },
  { header: 'title', get: (c) => c.title },
  { header: 'title_ar', get: (c) => c.title_ar },
  { header: 'title_sorani', get: (c) => c.title_sorani },
  { header: 'title_badini', get: (c) => c.title_badini },
  { header: 'address', get: (c) => c.address },
  { header: 'beneficiaries', get: (c) => c.beneficiaries },
  { header: 'goal_amount', get: (c) => c.goal_amount },
  { header: 'raised_amount', get: (c) => c.raised_amount },
  { header: 'status', get: (c) => c.status },
  { header: 'owner_user_id', get: (c) => c.owner_user_id ?? '' },
  { header: 'owner_name', get: (c) => c.owner_name ?? '' },
  { header: 'owner_phone', get: (c) => c.owner_phone ?? '' },
]

function formatAmount(s: string): string {
  const n = parseFloat(s)
  if (!isFinite(n)) return s
  return n.toLocaleString()
}

function Progress({ raised, goal }: { raised: number; goal: number }) {
  if (goal <= 0) return null
  const pct = Math.min(100, Math.round((raised / goal) * 100))
  return (
    <div className="progress" aria-label={`${pct}% funded`}>
      <div className="progress-bar" style={{ width: `${pct}%` }} />
    </div>
  )
}

export default function CampaignsPage() {
  const [page, setPage] = useState(1)
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminCampaign> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<AdminCampaign | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<AdminCampaign | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<AdminCampaign>((c) => c.id)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<AdminPageResp<AdminCampaign>>('/api/admin/campaigns', {
        params: { page, per_page: PER_PAGE, q: q || undefined },
      })
      .then((res) => {
        if (!cancelled) setResp(res.data)
      })
      .catch((e) => {
        if (!cancelled) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [page, q, refreshTick])

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/campaigns/${id}`, normalizeCampaignPatch(patch))
      toast.success(t('toast.saved', { noun: `${t('noun.campaign')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/campaigns`, normalizeCampaignPatch(data))
      toast.success(t('toast.created', { noun: `${t('noun.campaign')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/campaigns/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.campaign')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const applyBulkDelete = useCallback(async () => {
    const ids = [...sel.selected]
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/campaigns/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])


  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const columns: Column<AdminCampaign>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (c) => <strong>#{c.id}</strong> },
    {
      key: 'title',
      header: t('col.title'),
      cell: (c) => (
        <div className="cell-stack">
          <strong>{c.title}</strong>
          {c.title_ar && <span className="muted">{c.title_ar}</span>}
        </div>
      ),
    },
    { key: 'address', header: t('col.location'), cell: (c) => c.address },
    {
      key: 'owner',
      header: t('nav.beneficiary'),
      cell: (c) => {
        if (!c.owner_user_id) return <span className="muted">—</span>
        return (
          <div className="cell-stack">
            <Link to={`/detail/users/${c.owner_user_id}`} style={{ fontWeight: 700 }}>
              {t('common.user_ref', { id: c.owner_user_id })}
            </Link>
            {c.owner_name && <span>{c.owner_name}</span>}
            {c.owner_phone && <span className="muted">{c.owner_phone}</span>}
          </div>
        )
      },
    },
    {
      key: 'progress',
      header: t('col.raised_goal'),
      align: 'right',
      cell: (c) => {
        const raised = parseFloat(c.raised_amount) || 0
        const goal = parseFloat(c.goal_amount) || 0
        return (
          <div className="cell-stack" style={{ alignItems: 'flex-end' }}>
            <strong>
              {formatAmount(c.raised_amount)} / {formatAmount(c.goal_amount)}{' '}
              <span className="muted">IQD</span>
            </strong>
            <Progress raised={raised} goal={goal} />
          </div>
        )
      },
    },
    {
      key: 'beneficiaries',
      header: t('col.beneficiaries'),
      align: 'right',
      cell: (c) => <span>{c.beneficiaries}</span>,
    },
    {
      key: 'status',
      header: t('col.status'),
      width: '110px',
      cell: (c) => {
        const meta = STATUS_BADGES[c.status] ?? STATUS_BADGES.active
        return <span className={`badge tone-${meta.tone}`}>{statusLabel(c.status)}</span>
      },
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '170px',
      cell: (c) => (
        <>
          <Link className="row-edit-btn" to={`/detail/campaigns/${c.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(c)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(c)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.campaigns.title')}</h1>
          <p className="muted">
            {resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}
          </p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.campaigns.search_placeholder')}
            style={{ width: '220px' }}
          />
          <ExportCsvButton
            rows={resp?.items ?? []}
            columns={CSV_COLUMNS}
            filenameBase="campaigns"
            title={t('nav.campaigns')}
            module="campaigns"
          />
          <button onClick={() => setCreating(true)}>{t('page.campaigns.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<AdminCampaign>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(c) => c.id}
        loading={loading}
        empty={t('empty.campaigns')}
        selectable={sel.forRows(resp?.items ?? [])}
      />
      <Pagination
        page={page}
        totalPages={resp?.total_pages ?? 1}
        onPageChange={setPage}
        disabled={loading}
      />
      {/* Bulk bar shows only the Delete N button (no status column). */}
      {sel.count > 0 && (
        <div className="bulk-bar" role="region" aria-label={t('common.bulk_actions')}>
          <span><strong>{sel.count}</strong> {t('noun.campaign')} {t('common.selected')}</span>
          <button
            className="danger"
            onClick={async () => {
              const { ok, fail } = await applyBulkDelete()
              if (fail === 0) toast.success(t('bulk.deleted', { ok, noun: t('noun.campaign') }))
              else toast.info(t('bulk.del_mixed', { ok, fail }))
            }}
          >
            {t('common.delete')} {sel.count}
          </button>
          <button className="secondary" onClick={sel.clear}>{t('common.clear')}</button>
        </div>
      )}
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.campaign') }) : editing ? t('common.modal_edit', { noun: t('noun.campaign'), id: editing.id }) : ''}
        // Pre-translate the lifecycle string into the human label the
        // select expects, and default new campaigns to Active so the admin
        // doesn't have to click into the dropdown for the common case.
        initial={
          creating
            ? { status: STATUS_ACTIVE_LABEL }
            : editing
            ? { ...(editing as unknown as Record<string, unknown>), status: statusToLabel(editing.status) }
            : {}
        }
        fields={CAMPAIGN_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.campaign'), id: deleting.id }) : ''}
        message={deleting ? `${t('common.confirm_delete_body', { name: deleting.title })} ${t('page.campaigns.delete_extra')}` : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
