import { useCallback, useEffect, useMemo, useState, useRef } from 'react'
import RowDeleteButton from '../components/RowDeleteButton'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import StatusCell from '../components/StatusCell'
import type {
  AdminPageResp,
  BeneficiaryCase,
  ProjectRequest,
} from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import EditModal, { type FieldSpec } from '../components/EditModal'
import BulkBar from '../components/BulkBar'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { downloadCsv, type CsvColumn } from '../lib/csv'
import { HighlightBanner, useHighlightedRow } from '../lib/useHighlightedRow'
import { stripeForStatus } from '../lib/statusColors'
import { IRAQ_GOVERNORATES } from '../lib/iraqGovernorates'
import { useFieldRules, type FieldRuleState } from '../lib/fieldRules'

const CASE_CSV_COLUMNS: CsvColumn<BeneficiaryCase>[] = [
  { header: 'id', get: (r) => r.id },
  { header: 'case_code', get: (r) => r.case_code },
  { header: 'public_title', get: (r) => r.public_title },
  { header: 'user_id', get: (r) => r.user_id },
  { header: 'city', get: (r) => r.city },
  { header: 'district', get: (r) => r.district },
  { header: 'family_members_count', get: (r) => r.family_members_count },
  { header: 'priority_level', get: (r) => r.priority_level },
  { header: 'verification_status', get: (r) => r.verification_status },
  { header: 'public_visibility', get: (r) => r.public_visibility },
  { header: 'updated_at', get: (r) => r.updated_at },
]
const REQUEST_CSV_COLUMNS: CsvColumn<ProjectRequest>[] = [
  { header: 'id', get: (r) => r.id },
  { header: 'user_id', get: (r) => r.user_id },
  { header: 'project_title', get: (r) => r.project_title },
  { header: 'category', get: (r) => r.category },
  { header: 'amount_needed', get: (r) => r.amount_needed },
  { header: 'raised_amount', get: (r) => r.raised_amount },
  { header: 'currency', get: (r) => r.currency },
  { header: 'location', get: (r) => r.location },
  { header: 'beneficiary_community_name', get: (r) => r.beneficiary_community_name },
  { header: 'people_affected_total', get: (r) => r.people_affected_total },
  { header: 'status', get: (r) => r.status },
  { header: 'updated_at', get: (r) => r.updated_at },
]

type Tab = 'cases' | 'requests'

const PER_PAGE = 20

const CASE_STATUSES = [
  'all',
  'draft',
  'submitted',
  'under_review',
  'needs_changes',
  'approved',
  'rejected',
  'archived',
]
const EDITABLE_CASE_STATUSES = CASE_STATUSES.filter((s) => s !== 'all')

const REQUEST_STATUSES = [
  'all',
  'pending',
  'submitted',
  'under_review',
  'approved',
  'rejected',
]
const EDITABLE_REQUEST_STATUSES = REQUEST_STATUSES.filter((s) => s !== 'all')

const PRIORITY_LEVELS = ['low', 'medium', 'high', 'urgent']
const CASE_VISIBILITY = ['code_only', 'summary', 'hidden']
const CASE_GENDERS = ['male', 'female']
const CASE_MARITAL_STATUSES = ['single', 'married', 'widowed', 'divorced']

// Note #32 — every field an admin actually fills in when adding/editing a
// case is now Field-Rules-driven: `required` comes from the "case_<key>"
// row in registration_field_rules (Dashboard Settings → Field Rules)
// instead of being hardcoded here, so a Super-Admin can flip Required/
// Optional per field without a code change. Workflow fields (priority,
// verification status, visibility, review notes) are admin-set operational
// state rather than applicant data, so they're deliberately NOT in the
// field-rules set and keep their existing behavior.
// `city` is relabeled "Governorate" and switched to a dropdown (the client's
// ask) — same underlying DB column/API field, just a structured input.
function buildCaseFields(
  state: Record<string, FieldRuleState>,
  locale: string | undefined,
  t: (key: string) => string,
): FieldSpec[] {
  const governorateLabels: Record<string, string> = {}
  for (const g of IRAQ_GOVERNORATES) {
    governorateLabels[g.value] = locale === 'ar' || locale === 'ckb' || locale === 'kmr' ? g.ar : g.en
  }
  const genderLabels: Record<string, string> = { male: t('option.gender_male'), female: t('option.gender_female') }
  const maritalLabels: Record<string, string> = {
    single: t('option.marital_single'), married: t('option.marital_married'),
    widowed: t('option.marital_widowed'), divorced: t('option.marital_divorced'),
  }
  // ruleKey defaults to the FieldSpec key; a handful of DB columns are named
  // differently from their field-rules row (city -> governorate, etc).
  const isRequired = (ruleKey: string) => state[ruleKey] === 'required'
  const isHidden = (ruleKey: string) => state[ruleKey] === 'hidden'
  const fields: (FieldSpec & { ruleKey?: string })[] = [
    { key: 'public_title',         label: 'Public title (EN)', labelKey: 'field.public_title_en',  type: 'text',     required: isRequired('public_title') || (state.public_title === undefined) },
    { key: 'public_title_ar',      label: 'Public title (AR)', labelKey: 'field.public_title_ar',  type: 'text',     dir: 'rtl' },
    { key: 'public_title_sorani',  label: 'Public title (Sorani)', labelKey: 'field.public_title_sorani', type: 'text',  dir: 'rtl' },
    { key: 'public_title_badini',  label: 'Public title (Badini)', labelKey: 'field.public_title_badini', type: 'text',  dir: 'rtl' },
    { key: 'full_name',            label: 'Full name', labelKey: 'field.full_name',          type: 'text',     required: isRequired('full_name') },
    { key: 'national_id',          label: 'National ID', labelKey: 'field.national_id',        type: 'text',     required: isRequired('national_id') },
    { key: 'gender',                label: 'Gender', labelKey: 'field.gender',              type: 'select',   options: CASE_GENDERS, optionLabels: genderLabels, required: isRequired('gender') },
    { key: 'date_of_birth',        label: 'Date of birth', labelKey: 'field.date_of_birth',      type: 'date',     required: isRequired('date_of_birth') },
    { key: 'marital_status',       label: 'Marital status', labelKey: 'field.marital_status',     type: 'select',   options: CASE_MARITAL_STATUSES, optionLabels: maritalLabels, required: isRequired('marital_status') },
    { key: 'phone',                label: 'Phone', labelKey: 'field.phone',              type: 'text',     required: isRequired('phone') },
    { key: 'city',                 label: 'Governorate', labelKey: 'field.governorate',        type: 'select',   options: IRAQ_GOVERNORATES.map((g) => g.value), optionLabels: governorateLabels, required: isRequired('governorate'), ruleKey: 'governorate' },
    { key: 'district',             label: 'Neighborhood / District', labelKey: 'field.district', type: 'text', required: isRequired('district') },
    { key: 'family_members_count', label: 'Family members', labelKey: 'field.family_members',     type: 'number',   required: isRequired('family_members_count') },
    { key: 'income_amount',        label: 'Income amount', labelKey: 'field.income_amount',      type: 'number',   required: isRequired('income_amount') },
    { key: 'priority_level',       label: 'Priority', labelKey: 'field.priority',           type: 'select',   options: PRIORITY_LEVELS },
    { key: 'verification_status',  label: 'Verification status', labelKey: 'field.verification_status',type: 'select',   options: EDITABLE_CASE_STATUSES },
    { key: 'public_visibility',    label: 'Public visibility', labelKey: 'field.public_visibility',  type: 'select',   options: CASE_VISIBILITY },
    { key: 'housing_status',       label: 'Housing status', labelKey: 'field.housing_status',     type: 'text',     required: isRequired('housing_status') },
    { key: 'work_status',          label: 'Work status', labelKey: 'field.work_status',        type: 'text',     required: isRequired('work_status') },
    { key: 'address',              label: 'Address', labelKey: 'field.address',            type: 'textarea', rows: 2, required: isRequired('address') },
    { key: 'health_status',        label: 'Health status', labelKey: 'field.health_status',      type: 'textarea', rows: 2, required: isRequired('health_status') },
    { key: 'education_status',     label: 'Education status', labelKey: 'field.education_status',   type: 'textarea', rows: 2, required: isRequired('education_status') },
    { key: 'actual_needs',         label: 'Actual needs', labelKey: 'field.actual_needs',       type: 'textarea', rows: 3, required: isRequired('actual_needs') },
    { key: 'review_notes',         label: 'Review notes', labelKey: 'field.review_notes',       type: 'textarea', rows: 3 },
  ]
  return fields.filter((f) => !isHidden(f.ruleKey ?? f.key))
}

const REQUEST_FIELDS: FieldSpec[] = [
  { key: 'project_title',          label: 'Title (EN)', labelKey: 'field.title_en',     type: 'text',     required: true },
  { key: 'project_title_ar',       label: 'Title (AR)', labelKey: 'field.title_ar',     type: 'text',     dir: 'rtl' },
  { key: 'project_title_sorani',   label: 'Title (Sorani)', labelKey: 'field.title_sorani', type: 'text',     dir: 'rtl' },
  { key: 'project_title_badini',   label: 'Title (Badini)', labelKey: 'field.title_badini', type: 'text',     dir: 'rtl' },
  { key: 'category',               label: 'Category', labelKey: 'field.category',       type: 'text',     required: true },
  { key: 'status',                 label: 'Status', labelKey: 'field.status',         type: 'select',   options: EDITABLE_REQUEST_STATUSES },
  { key: 'amount_needed',          label: 'Amount needed', labelKey: 'field.amount_needed',  type: 'number' },
  { key: 'currency',               label: 'Currency', labelKey: 'field.currency',       type: 'text',     placeholder: 'IQD' },
  { key: 'location',               label: 'Location', labelKey: 'field.location',       type: 'text',     required: true },
  { key: 'beneficiary_community_name', label: 'Community', labelKey: 'field.community',  type: 'text',     required: true },
  { key: 'people_affected_total',  label: 'People affected', labelKey: 'field.people_affected',type: 'number' },
  { key: 'male_count',             label: 'Male count', labelKey: 'field.male_count',     type: 'number' },
  { key: 'female_count',           label: 'Female count', labelKey: 'field.female_count',   type: 'number' },
  { key: 'timeline_target',        label: 'Timeline target', labelKey: 'field.timeline_target',type: 'text' },
  { key: 'contact_person_name',    label: 'Contact name', labelKey: 'field.contact_name',   type: 'text' },
  { key: 'contact_phone',          label: 'Contact phone', labelKey: 'field.contact_phone',  type: 'text' },
  { key: 'contact_email',          label: 'Contact email', labelKey: 'field.contact_email',  type: 'text' },
  { key: 'summary',                label: 'Summary (EN)', labelKey: 'field.summary_en',   type: 'textarea', rows: 3, required: true },
  { key: 'summary_ar',             label: 'Summary (AR)', labelKey: 'field.summary_ar',   type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_long',       label: 'Description (EN)', labelKey: 'field.description_en', type: 'textarea', rows: 4, required: true },
  { key: 'description_long_ar',    label: 'Description (AR)', labelKey: 'field.description_ar', type: 'textarea', rows: 4, dir: 'rtl' },
  { key: 'other_notes',            label: 'Other notes', labelKey: 'field.other_notes',    type: 'textarea', rows: 3 },
]

// Create form adds the required user_id at the top.
const REQUEST_CREATE_FIELDS: FieldSpec[] = [
  { key: 'user_id', label: 'User ID', labelKey: 'field.user_id', type: 'number', required: true },
  ...REQUEST_FIELDS,
]

function priorityClass(p: string): string {
  switch (p) {
    case 'urgent':
      return 'failed'
    case 'high':
      return 'pending'
    case 'low':
      return 'role-3'
    default:
      return 'role-1'
  }
}

function formatAmount(s: string | number): string {
  const n = typeof s === 'number' ? s : parseFloat(s)
  if (!isFinite(n)) return String(s)
  return n.toLocaleString()
}

export default function BeneficiaryPage() {
  const [tab, setTab] = useState<Tab>('cases')
  const { t } = useI18n()
  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.beneficiary.title')}</h1>
        </div>
        <div className="tab-row">
          <button
            className={tab === 'cases' ? '' : 'secondary'}
            onClick={() => setTab('cases')}
          >
            {t('page.beneficiary.tab_cases')}
          </button>
          <button
            className={tab === 'requests' ? '' : 'secondary'}
            onClick={() => setTab('requests')}
          >
            {t('page.beneficiary.tab_requests')}
          </button>
        </div>
      </div>

      {tab === 'cases' ? <CasesTab /> : <RequestsTab />}
    </div>
  )
}

function CasesTab() {
  const statusLabel = useStatusLabel()
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState<string>('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<BeneficiaryCase> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<BeneficiaryCase | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<BeneficiaryCase | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t, locale } = useI18n()
  const sel = useSelection<BeneficiaryCase>((r) => r.id)
  // Live-feed click → pulse the matching case row.
  const highlight = useHighlightedRow()
  // Note #32 — Field Rules (Dashboard Settings) drives which of these
  // fields are Required vs Optional.
  const { state: caseFieldState } = useFieldRules('case_')
  const caseFields = useMemo(() => buildCaseFields(caseFieldState, locale, t), [caseFieldState, locale, t])
  const caseCreateFields = useMemo(
    () => [{ key: 'user_id', label: 'User ID (optional)', labelKey: 'field.user_id_optional', type: 'number' as const }, ...caseFields],
    [caseFields],
  )

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<BeneficiaryCase>>('/api/admin/beneficiary_cases', {
        params: { page, per_page: PER_PAGE, status, q: q || undefined },
      })
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
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh every 5s. New beneficiary submissions
  // should surface to admin without manual reload.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/beneficiary_cases/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.case')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number; case_code: string }>(`/api/admin/beneficiary_cases`, data)
      toast.success(`${t('toast.created', { noun: `${t('noun.case')} #${res.data.id}` })} (${res.data.case_code})`)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const applyBulkStatus = useCallback(
    async (newStatus: string) => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.post(`/api/admin/beneficiary_cases/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/beneficiary_cases/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/beneficiary_cases/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.case')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`cases-${new Date().toISOString().slice(0, 10)}.csv`, rows, CASE_CSV_COLUMNS)
  }

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const columns: Column<BeneficiaryCase>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (r) => <strong>#{r.id}</strong> },
    {
      key: 'code',
      header: t('col.case_code'),
      cell: (r) => <code style={{ background: 'transparent', padding: 0 }}>{r.case_code}</code>,
    },
    {
      key: 'title',
      header: t('col.title'),
      cell: (r) => (
        <div className="cell-stack">
          <strong>{r.public_title}</strong>
          {r.public_title_ar && <span className="muted">{r.public_title_ar}</span>}
        </div>
      ),
    },
    {
      key: 'user',
      header: t('col.submitted_by'),
      cell: (r) =>
        r.user_id ? t('common.user_ref_lc', { id: r.user_id }) : <span className="muted">—</span>,
    },
    {
      key: 'location',
      header: t('col.location'),
      cell: (r) =>
        r.city || r.district ? (
          <span>
            {[r.city, r.district].filter(Boolean).join(' · ')}
          </span>
        ) : (
          <span className="muted">—</span>
        ),
    },
    {
      key: 'family',
      header: t('col.family'),
      align: 'right',
      cell: (r) => r.family_members_count ?? <span className="muted">—</span>,
    },
    {
      key: 'priority',
      header: t('col.priority'),
      cell: (r) => (
        <span className={`badge ${priorityClass(r.priority_level)}`}>
          {statusLabel(r.priority_level)}
        </span>
      ),
    },
    {
      key: 'status',
      header: t('col.status'),
      cell: (r) => (
        <StatusCell
          // Note #15 — legacy self-submitted cases can have a null
          // verification_status (backend now defaults new ones to
          // "submitted"); fall back the same way so an old row still renders
          // a normal, editable status instead of an empty/uncontrolled select.
          value={r.verification_status ?? 'submitted'}
          allowed={EDITABLE_CASE_STATUSES}
          onSave={(next) =>
            api.post(`/api/admin/beneficiary_cases/${r.id}/status`, { status: next })
          }
          label={t('common.case_ref', { id: r.id })}
        />
      ),
    },
    {
      key: 'updated',
      header: t('col.updated'),
      cell: (r) => <span className="muted">{r.updated_at?.slice(0, 10)}</span>,
    },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (r) => (
        <>
          <Link className="row-edit-btn" to={`/detail/beneficiary_cases/${r.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(r)}>{t('common.edit')}</button>
          <RowDeleteButton onClick={() => setDeleting(r)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <p className="muted">{resp ? t('common.bene_total_cases', { n: resp.total_items }) : t('common.loading')}</p>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.beneficiary.cases_search_placeholder')}
            style={{ width: '220px' }}
          />
          <select
            value={status}
            onChange={(e) => {
              setStatus(e.target.value)
              setPage(1)
              sel.clear()
            }}
            style={{ width: 'auto' }}
          >
            {CASE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {statusLabel(s)}
              </option>
            ))}
          </select>
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.beneficiary.new_case')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.case')} />
      <Table<BeneficiaryCase>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(r) => r.id}
        loading={loading}
        empty={t('empty.cases')}
        selectable={sel.forRows(resp?.items ?? [])}
        rowProps={(r) => ({
          className: [
            highlight.isHighlighted(r.id) ? 'is-highlighted' : '',
            stripeForStatus(r.verification_status ?? 'submitted'),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(r.id),
        })}
      />
      <Pagination
        page={page}
        totalPages={resp?.total_pages ?? 1}
        onPageChange={setPage}
        disabled={loading}
      />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_CASE_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="cases"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.case'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body_code', { noun: t('noun.case'), code: deleting.case_code }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.case') }) : editing ? t('common.modal_edit', { noun: t('noun.case'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={creating ? caseCreateFields : caseFields}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}

function RequestsTab() {
  const statusLabel = useStatusLabel()
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState<string>('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<ProjectRequest> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<ProjectRequest | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<ProjectRequest | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t } = useI18n()
  const sel = useSelection<ProjectRequest>((r) => r.id)
  // Live-feed click → pulse the matching project-request row.
  const highlight = useHighlightedRow()

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<ProjectRequest>>(
        '/api/admin/beneficiary_project_requests',
        { params: { page, per_page: PER_PAGE, status, q: q || undefined } },
      )
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
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh project requests tab every 5s.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/beneficiary_project_requests/${id}`, patch)
      toast.success(t('toast.saved', { noun: `${t('noun.project_request')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(`/api/admin/beneficiary_project_requests`, data)
      toast.success(t('toast.created', { noun: `${t('noun.project_request')} #${res.data.id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const applyBulkStatus = useCallback(
    async (newStatus: string) => {
      const ids = [...sel.selected]
      const results = await Promise.allSettled(
        ids.map((id) => api.post(`/api/admin/beneficiary_project_requests/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/beneficiary_project_requests/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/beneficiary_project_requests/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.project_request')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  // Phase 23 — Publish to donors. Backend's PublishProjectRequest copies the
  // approved row into the `campaigns` table with owner_user_id set, which
  // (a) makes it visible to donors at /api/campaigns, and (b) activates the
  // "donation received on your project" notification for the beneficiary.
  const handlePublish = useCallback(
    async (r: ProjectRequest) => {
      try {
        const res = await api.post<{ id: number; already?: boolean; message?: string }>(
          `/api/admin/beneficiary_project_requests/${r.id}/publish`, {},
        )
        if (res.data.already) {
          toast.info(res.data.message ?? t('page.beneficiary.already_published', { id: res.data.id }))
        } else {
          toast.success(t('page.beneficiary.published', { name: r.project_title, id: res.data.id }))
        }
      } catch (e) {
        toast.error(describeError(e))
      }
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`requests-${new Date().toISOString().slice(0, 10)}.csv`, rows, REQUEST_CSV_COLUMNS)
  }

  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const columns: Column<ProjectRequest>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (r) => <strong>#{r.id}</strong> },
    {
      key: 'title',
      header: t('col.project'),
      cell: (r) => (
        <div className="cell-stack">
          <strong>{r.project_title}</strong>
          {r.project_title_ar && <span className="muted">{r.project_title_ar}</span>}
        </div>
      ),
    },
    { key: 'category', header: t('col.category'), cell: (r) => r.category },
    {
      key: 'user',
      header: t('col.submitted_by'),
      cell: (r) => t('common.user_ref_lc', { id: r.user_id }),
    },
    {
      key: 'community',
      header: t('col.community'),
      cell: (r) => r.beneficiary_community_name,
    },
    {
      key: 'amount',
      header: t('col.goal'),
      align: 'right',
      cell: (r) => (
        <strong>
          {formatAmount(r.amount_needed)} <span className="muted">{r.currency}</span>
        </strong>
      ),
    },
    {
      key: 'raised',
      header: t('col.raised'),
      align: 'right',
      cell: (r) => formatAmount(r.raised_amount),
    },
    {
      key: 'people',
      header: t('col.people'),
      align: 'right',
      cell: (r) => r.people_affected_total ?? <span className="muted">—</span>,
    },
    {
      key: 'status',
      header: t('col.status'),
      cell: (r) => (
        <StatusCell
          value={r.status}
          allowed={EDITABLE_REQUEST_STATUSES}
          onSave={(next) =>
            api.post(`/api/admin/beneficiary_project_requests/${r.id}/status`, { status: next })
          }
          label={t('common.request_ref', { id: r.id })}
        />
      ),
    },
    {
      key: 'actions', header: t('common.actions'), width: '260px',
      cell: (r) => (
        <>
          <Link className="row-edit-btn" to={`/detail/beneficiary_project_requests/${r.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(r)}>{t('common.edit')}</button>
          {/* Phase 23 — Publish to donors. Only available on approved
              requests. Disabled state for non-approved gives admin a
              hint without hiding the affordance entirely. */}
          {r.status === 'approved' && (
            <button
              className="row-edit-btn"
              onClick={() => handlePublish(r)}
              title={t('page.beneficiary.publish_title')}
            >
              {t('page.beneficiary.publish')}
            </button>
          )}
          <RowDeleteButton onClick={() => setDeleting(r)} />
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <p className="muted">{resp ? t('common.bene_total_requests', { n: resp.total_items }) : t('common.loading')}</p>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.beneficiary.requests_search_placeholder')}
            style={{ width: '220px' }}
          />
          <select
            value={status}
            onChange={(e) => {
              setStatus(e.target.value)
              setPage(1)
              sel.clear()
            }}
            style={{ width: 'auto' }}
          >
            {REQUEST_STATUSES.map((s) => (
              <option key={s} value={s}>
                {statusLabel(s)}
              </option>
            ))}
          </select>
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.beneficiary.new_request')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.project_request')} />
      <Table<ProjectRequest>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(r) => r.id}
        loading={loading}
        empty={t('empty.requests')}
        selectable={sel.forRows(resp?.items ?? [])}
        rowProps={(r) => ({
          className: [
            highlight.isHighlighted(r.id) ? 'is-highlighted' : '',
            stripeForStatus(r.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(r.id),
        })}
      />
      <Pagination
        page={page}
        totalPages={resp?.total_pages ?? 1}
        onPageChange={setPage}
        disabled={loading}
      />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_REQUEST_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="requests"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.project_request'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body', { name: deleting.project_title }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.project_request') }) : editing ? t('common.modal_edit', { noun: t('noun.project_request'), id: editing.id }) : ''}
        initial={creating ? {} : (editing as unknown as Record<string, unknown> ?? {})}
        fields={creating ? REQUEST_CREATE_FIELDS : REQUEST_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}
