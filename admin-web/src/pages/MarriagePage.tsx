import { useCallback, useEffect, useMemo, useState } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import type { MarriageProfile } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import BulkBar from '../components/BulkBar'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { type CsvColumn } from '../lib/csv'
import { useFieldRules, type FieldRuleState } from '../lib/fieldRules'

const MARRIAGE_CSV_COLUMNS: CsvColumn<MarriageProfile>[] = [
  { header: 'id', get: (p) => p.id },
  { header: 'profile_code', get: (p) => p.profile_code },
  { header: 'gender', get: (p) => p.gender },
  { header: 'age', get: (p) => p.age },
  { header: 'city', get: (p) => p.city },
  { header: 'visibility_level', get: (p) => p.visibility_level },
  { header: 'subscription_status', get: (p) => p.subscription_status },
  { header: 'status', get: (p) => p.status },
  { header: 'created_at', get: (p) => p.created_at },
]

type Resp = { success: true; items: MarriageProfile[] }

const STATUSES = ['all', 'submitted', 'under_review', 'active', 'paused', 'matched', 'rejected', 'closed']
const EDITABLE_STATUSES = STATUSES.filter((s) => s !== 'all')
const VISIBILITY_LEVELS = ['private', 'employee_only', 'matched_summary']
// Note #17 — was ['free','paid','waived']. "Free" was misleading (only the
// search feature is actually free); replaced with the real package tiers.
// 'bronze' is the entry-level tier that replaces the old 'free' default.
const SUBSCRIPTION_STATUSES = ['bronze', 'silver', 'gold', 'diamond', 'vip']

// Note #33 — gender/age/city/social_summary/private_notes (the applicant
// data the profile owner actually submits) are Field-Rules-driven via the
// "marriage_" prefix (migration 056), same mechanism as the Beneficiary
// case form (Note #32). visibility_level/subscription_status/status/user_id
// are admin-set operational fields, not applicant data, so they stay fixed.
function buildMarriageFields(state: Record<string, FieldRuleState>): FieldSpec[] {
  const isRequired = (key: string) => state[key] === 'required'
  const isHidden = (key: string) => state[key] === 'hidden'
  const fields: FieldSpec[] = [
    { key: 'gender',              label: 'Gender', labelKey: 'field.gender',              type: 'text',     required: isRequired('gender') },
    { key: 'age',                 label: 'Age', labelKey: 'dbfield.age',        type: 'number',   required: isRequired('age') },
    { key: 'city',                label: 'City', labelKey: 'field.city',                type: 'text',     required: isRequired('city') },
    { key: 'visibility_level',    label: 'Visibility', labelKey: 'field.visibility',          type: 'select', options: VISIBILITY_LEVELS },
    { key: 'subscription_status', label: 'Subscription', labelKey: 'field.subscription',        type: 'select', options: SUBSCRIPTION_STATUSES },
    { key: 'status',              label: 'Status', labelKey: 'field.status',              type: 'select', options: EDITABLE_STATUSES },
    { key: 'social_summary',      label: 'Social summary', labelKey: 'field.social_summary',      type: 'textarea', rows: 3, required: isRequired('social_summary') },
    { key: 'private_notes',       label: 'Private notes', labelKey: 'field.private_notes',       type: 'textarea', rows: 3, required: isRequired('private_notes') },
  ]
  return fields.filter((f) => !isHidden(f.key))
}

export default function MarriagePage() {
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<Resp | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<MarriageProfile | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<MarriageProfile | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<MarriageProfile>((p) => p.id)
  const { state: marriageFieldState } = useFieldRules('marriage_')
  const editFields = useMemo(() => buildMarriageFields(marriageFieldState), [marriageFieldState])
  const createFields = useMemo(
    () => [{ key: 'user_id', label: 'User ID', labelKey: 'field.user_id', type: 'number' as const, required: true }, ...editFields],
    [editFields],
  )

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setErr(null)
    api
      .get<Resp>('/api/marriage', { params: { status, q: q || undefined, limit: 100 } })
      .then((res) => {
        if (!cancelled) setResp(res.data)
      })
      .catch((e) => {
        if (!cancelled) setErr(describeError(e))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [status, q, refreshTick])

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/marriage/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.profile')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number; profile_code: string }>(`/api/admin/marriage`, data)
      toast.success(`${t('toast.created', { noun: `${t('noun.profile')} #${res.data.id}` })} (${res.data.profile_code})`)
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
        ids.map((id) => api.post(`/api/admin/marriage/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/marriage/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/marriage/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.profile')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )


  const columns: Column<MarriageProfile>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (p) => <strong>#{p.id}</strong> },
    {
      key: 'code',
      header: t('col.profile_code'),
      cell: (p) => <code style={{ background: 'transparent', padding: 0 }}>{p.profile_code}</code>,
    },
    { key: 'gender', header: t('col.gender'), cell: (p) => p.gender ?? <span className="muted">—</span> },
    { key: 'age', header: t('col.age'), align: 'right', cell: (p) => p.age ?? <span className="muted">—</span> },
    { key: 'city', header: t('col.city'), cell: (p) => p.city ?? <span className="muted">—</span> },
    {
      key: 'summary',
      header: t('col.summary'),
      cell: (p) =>
        p.social_summary ? (
          <span>{p.social_summary}</span>
        ) : (
          <span className="muted">—</span>
        ),
    },
    {
      key: 'visibility',
      header: t('col.visibility'),
      cell: (p) => <span className="badge">{statusLabel(p.visibility_level)}</span>,
    },
    {
      key: 'subscription',
      header: t('col.subscription'),
      cell: (p) => <span className="badge">{statusLabel(p.subscription_status)}</span>,
    },
    {
      key: 'status',
      header: t('col.status'),
      cell: (p) => (
        <StatusCell
          value={p.status}
          allowed={STATUSES.filter((s) => s !== 'all')}
          onSave={(next) => api.post(`/api/admin/marriage/${p.id}/status`, { status: next })}
          label={`Profile #${p.id}`}
        />
      ),
    },
    {
      key: 'created',
      header: t('col.created'),
      cell: (p) => <span className="muted">{p.created_at?.slice(0, 10)}</span>,
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (p) => (
        <>
          <Link className="row-edit-btn" to={`/detail/marriage/${p.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(p)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(p)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.marriage.title')}</h1>
          <p className="muted">{resp ? `${resp.items.length} ${t('common.shown')}` : t('common.loading')}</p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); sel.clear() }}
            placeholder={t('page.marriage.search_placeholder')}
            style={{ width: '200px' }}
          />
          <select value={status} onChange={(e) => { setStatus(e.target.value); sel.clear() }} style={{ width: 'auto' }}>
            {STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton
            rows={resp?.items ?? []}
            columns={MARRIAGE_CSV_COLUMNS}
            filenameBase="marriage"
            title={t('nav.marriage')}
            module="marriage"
          />
          <button onClick={() => setCreating(true)}>{t('page.marriage.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <Table<MarriageProfile>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(p) => p.id}
        loading={loading}
        empty={t('empty.marriage')}
        selectable={sel.forRows(resp?.items ?? [])}
      />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="profiles"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.profile'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body_code', { noun: t('noun.profile'), code: deleting.profile_code }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.profile') }) : editing ? t('common.modal_edit', { noun: t('noun.profile'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={creating ? createFields : editFields}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}
