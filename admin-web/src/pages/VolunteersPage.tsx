import { useCallback, useEffect, useState, useRef } from 'react'
import { Link } from 'react-router-dom'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { AdminMissionSignup, AdminPageResp, AdminVolunteerApp } from '../lib/api-types'
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
import { usePendingCounts } from '../lib/pendingCounts'
import {
  ALL_SKILL_KEYS,
  DAY_KEYS,
  SKILL_CATEGORIES,
  dayLabelFor,
  skillLabelFor,
} from '../lib/skillCatalogue'
import { SKILL_ICON, colorForSkill } from '../lib/skillIcons'

const VOLUNTEER_CSV_COLUMNS: CsvColumn<AdminVolunteerApp>[] = [
  { header: 'id', get: (a) => a.id },
  { header: 'user_id', get: (a) => a.user_id },
  { header: 'full_name', get: (a) => a.full_name },
  { header: 'phone', get: (a) => a.phone },
  { header: 'city', get: (a) => a.city },
  { header: 'skills', get: (a) => a.skills },
  { header: 'availability', get: (a) => a.availability },
  { header: 'status', get: (a) => a.status },
  { header: 'created_at', get: (a) => a.created_at },
]

const PER_PAGE = 20

const STATUSES = ['all', 'submitted', 'approved', 'rejected', 'inactive']
const EDITABLE_STATUSES = STATUSES.filter((s) => s !== 'all')

const VOLUNTEER_FIELDS: FieldSpec[] = [
  { key: 'full_name',    label: 'Full name', labelKey: 'field.full_name',    type: 'text', required: true },
  { key: 'phone',        label: 'Phone', labelKey: 'field.phone',        type: 'text' },
  { key: 'city',         label: 'City', labelKey: 'field.city',         type: 'text' },
  { key: 'status',       label: 'Status', labelKey: 'field.status',       type: 'select', options: EDITABLE_STATUSES },
  { key: 'cv_link',      label: 'CV link', labelKey: 'field.cv_link',      type: 'text' },
  { key: 'availability', label: 'Availability notes', labelKey: 'field.availability_notes', type: 'textarea', rows: 2 },
  { key: 'skills',       label: 'Skills (free text)', labelKey: 'field.skills_free', type: 'textarea', rows: 3 },
  // Phase 26 — skill_tags is TEXT[] server-side. The modal still uses a
  // plain text input (comma-separated), and the page-level handlers
  // normalize the value before POST/PATCH (csvToArray).
  { key: 'skill_tags',   label: 'Skill tags (comma-separated canonical keys, e.g. driver_car, first_aid)', labelKey: 'field.skill_tags', type: 'text' },
  { key: 'other_skill',  label: 'Other skill', labelKey: 'field.other_skill',  type: 'text' },
  { key: 'experience',   label: 'Experience', labelKey: 'field.experience',   type: 'textarea', rows: 3 },
]

// csvToArray splits the admin's "driver_car, first_aid" input into an array
// that the backend's *[]string column accepts. Empty/blank → empty array.
function csvToArray(v: unknown): string[] {
  if (Array.isArray(v)) return v.map((s) => String(s).trim()).filter(Boolean)
  if (typeof v === 'string') {
    return v.split(',').map((s) => s.trim()).filter(Boolean)
  }
  return []
}

// normalizeVolunteerPayload runs csvToArray on skill_tags before any
// create/patch hits the server, so the SPA's UX (one text input) and the
// backend's typed column (TEXT[]) stay aligned.
function normalizeVolunteerPayload(
  data: Record<string, unknown>,
): Record<string, unknown> {
  if ('skill_tags' in data) {
    return { ...data, skill_tags: csvToArray(data.skill_tags) }
  }
  return data
}

const VOLUNTEER_CREATE_FIELDS: FieldSpec[] = [
  { key: 'user_id', label: 'User ID (optional)', labelKey: 'field.user_id_optional', type: 'number' },
  ...VOLUNTEER_FIELDS,
]

// Phase 21 — top-level wrapper with two tabs:
//   • Applications      → volunteer_applications table (existing)
//   • Mission signups   → volunteer_mission_signups (new — admin approves
//                         join / marks attendance / completion / no-show)
//
// Tab selection is local state — no URL param yet, but the `?highlight=`
// flow from the dashboard lands on whichever tab makes sense for the
// event type (event_type 'volunteer_application_submit' lands on
// applications; future 'volunteer_mission_join' / 'volunteer_attendance'
// would land on signups when that wiring is added).
type Tab = 'applications' | 'signups'

export default function VolunteersPage() {
  const [tab, setTab] = useState<Tab>('applications')
  const { t } = useI18n()
  const { counts } = usePendingCounts()
  // Show a small count badge on the tab so the admin can see at a glance
  // which queue has work waiting.
  function badge(n: number) {
    if (n <= 0) return null
    return <span className="nav-badge" style={{ marginInlineStart: 8 }}>{n}</span>
  }
  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.volunteers.title')}</h1>
        </div>
        <div className="tab-row">
          <button
            className={tab === 'applications' ? '' : 'secondary'}
            onClick={() => setTab('applications')}
          >
            {t('page.volunteers.tab_applications')} {badge(counts.volunteers)}
          </button>
          <button
            className={tab === 'signups' ? '' : 'secondary'}
            onClick={() => setTab('signups')}
          >
            {t('page.volunteers.tab_signups')} {badge(counts.mission_signups)}
          </button>
        </div>
      </div>
      {tab === 'applications' ? <ApplicationsTab /> : <MissionSignupsTab />}
    </div>
  )
}

function ApplicationsTab() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('all')
  const [q, setQ] = useState('')
  // Phase 26 — structured filters. 'all' = no filter.
  const [skillFilter, setSkillFilter] = useState('all')
  const [dayFilter, setDayFilter] = useState('all')
  const [resp, setResp] = useState<AdminPageResp<AdminVolunteerApp> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<AdminVolunteerApp | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<AdminVolunteerApp | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t, locale } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<AdminVolunteerApp>((a) => a.id)
  const highlight = useHighlightedRow()

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<AdminVolunteerApp>>('/api/admin/volunteer_applications', {
        params: {
          page,
          per_page: PER_PAGE,
          status,
          q: q || undefined,
          skill: skillFilter === 'all' ? undefined : skillFilter,
          day: dayFilter === 'all' ? undefined : dayFilter,
        },
      })
      .then(r => { if (!cancelled) setResp(r.data) })
      .catch(e => { if (!cancelled && !pollSilent.current) setErr(describeError(e)) })
      .finally(() => { if (!cancelled && !pollSilent.current) setLoading(false); pollSilent.current = false })
    return () => { cancelled = true }
  }, [page, status, q, skillFilter, dayFilter, refreshTick])

  // Phase 27 — live refresh applications every 5s. New volunteer
  // submissions should surface to admin without manual reload.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(
        `/api/admin/volunteer_applications/${id}`,
        normalizeVolunteerPayload(patch),
      )
      toast.success(t('toast.saved', { noun: `${t('noun.volunteer_application')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number }>(
        `/api/admin/volunteer_applications`,
        normalizeVolunteerPayload(data),
      )
      toast.success(t('toast.created', { noun: `${t('noun.volunteer_application')} #${res.data.id}` }))
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
        ids.map((id) => api.post(`/api/admin/volunteer_applications/${id}/status`, { status: newStatus })),
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
    const results = await Promise.allSettled(ids.map((id) => api.delete(`/api/admin/volunteer_applications/${id}`)))
    const ok = results.filter((r) => r.status === 'fulfilled').length
    sel.clear()
    setRefreshTick((t) => t + 1)
    return { ok, fail: results.length - ok }
  }, [sel])

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/volunteer_applications/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.volunteer_application')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`volunteers-${new Date().toISOString().slice(0, 10)}.csv`, rows, VOLUNTEER_CSV_COLUMNS)
  }

  const columns: Column<AdminVolunteerApp>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (a) => <strong>#{a.id}</strong> },
    {
      key: 'who', header: t('col.applicant'),
      cell: (a) => (
        <div className="cell-stack">
          <strong>{a.full_name}</strong>
          <span className="muted">{a.phone ?? a.user_phone ?? '—'}</span>
        </div>
      ),
    },
    { key: 'city', header: t('col.city'), cell: (a) => a.city ?? <span className="muted">—</span> },
    {
      key: 'skills',
      header: t('col.skills'),
      cell: (a) => {
        // Prefer the structured chips when present; show free-form
        // below the chips only when it differs from the auto-synthesized
        // CSV the backend builds.
        const keys = a.skill_tags ?? []
        const freeText = (a.skills ?? '').trim()
        const showFreeText =
          freeText.length > 0 &&
          freeText.toLowerCase() !== keys.join(', ').toLowerCase()
        if (keys.length === 0 && !showFreeText) {
          return <span className="muted">—</span>
        }
        return (
          <div className="cell-stack" style={{ gap: 4 }}>
            {keys.length > 0 && (
              <div className="row" style={{ flexWrap: 'wrap', gap: 4 }}>
                {keys.map((k) => {
                  const color = colorForSkill(k)
                  return (
                    <span
                      key={k}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 4,
                        padding: '2px 8px',
                        borderRadius: 99,
                        fontSize: 11,
                        fontWeight: 600,
                        color,
                        background: `${color}14`, // ~8% alpha
                        border: `1px solid ${color}40`, // ~25% alpha
                      }}
                    >
                      <span aria-hidden style={{ fontSize: 12 }}>
                        {SKILL_ICON[k] ?? '•'}
                      </span>
                      {skillLabelFor(k, locale)}
                    </span>
                  )
                })}
              </div>
            )}
            {showFreeText && (
              <span className="muted" style={{ fontSize: 12 }}>{freeText}</span>
            )}
          </div>
        )
      },
    },
    {
      key: 'avail',
      header: t('col.availability'),
      cell: (a) => {
        const rows = a.availability_schedule ?? []
        if (rows.length === 0) {
          return a.availability ? <span>{a.availability}</span> : <span className="muted">—</span>
        }
        // Compact two-column layout — day pill on the left, time on the right.
        return (
          <div className="cell-stack" style={{ gap: 3 }}>
            {rows.map((r) => (
              <div
                key={r.day}
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: 6,
                  fontSize: 11,
                }}
              >
                <span
                  style={{
                    display: 'inline-block',
                    width: 30,
                    padding: '1px 0',
                    textAlign: 'center',
                    borderRadius: 6,
                    fontWeight: 700,
                    fontSize: 10,
                    color: '#fff',
                    background: 'var(--accent, #4F46E5)',
                  }}
                >
                  {dayLabelFor(r.day, locale).slice(0, 3)}
                </span>
                <span style={{ fontFamily: 'monospace' }}>{r.from} – {r.to}</span>
              </div>
            ))}
          </div>
        )
      },
    },
    {
      key: 'status', header: t('col.status'),
      cell: (a) => (
        <StatusCell
          value={a.status}
          allowed={STATUSES.filter((s) => s !== 'all')}
          onSave={(next) => api.post(`/api/admin/volunteer_applications/${a.id}/status`, { status: next })}
          label={`Application #${a.id}`}
        />
      ),
    },
    { key: 'created', header: t('col.created'), cell: (a) => <span className="muted">{a.created_at?.slice(0, 10)}</span> },
    {
      key: 'actions', header: t('common.actions'), width: '170px',
      cell: (a) => (
        <>
          <Link className="row-edit-btn" to={`/detail/volunteer_applications/${a.id}`}>{t('common.view')}</Link>
          <button className="row-edit-btn" onClick={() => setEditing(a)}>{t('common.edit')}</button>
          <button className="row-delete-btn" onClick={() => setDeleting(a)}>{t('common.delete')}</button>
        </>
      ),
    },
  ]

  return (
    <div className="stack">
      {/* No <h1> here — the parent VolunteersPage wrapper owns the page
          title and tab row. We just render the secondary controls + table. */}
      <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
        <p className="muted" style={{ margin: 0 }}>
          {resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}
        </p>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.volunteers.search_placeholder')}
            style={{ width: '220px' }}
          />
          <select value={status} onChange={e => { setStatus(e.target.value); setPage(1); sel.clear() }} style={{ width: 'auto' }}>
            {STATUSES.map(s => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <select
            value={skillFilter}
            onChange={(e) => { setSkillFilter(e.target.value); setPage(1); sel.clear() }}
            style={{ width: 'auto' }}
            title={t('filter.by_skill')}
          >
            <option value="all">{t('filter.all_skills')}</option>
            {/* Group by category so the dropdown is scannable. The
                native <optgroup> handles the visual indentation. */}
            {SKILL_CATEGORIES.map((cat) => (
              <optgroup key={cat.key} label={`${cat.en}`}>
                {cat.skills.map((s) => (
                  <option key={s.key} value={s.key}>
                    {(SKILL_ICON[s.key] ?? '•') + ' ' + skillLabelFor(s.key, locale)}
                  </option>
                ))}
              </optgroup>
            ))}
            {/* Unused — ALL_SKILL_KEYS kept for future flat-iteration. */}
            {false && ALL_SKILL_KEYS.map((k) => <option key={k} value={k} />)}
          </select>
          <select
            value={dayFilter}
            onChange={(e) => { setDayFilter(e.target.value); setPage(1); sel.clear() }}
            style={{ width: 'auto' }}
            title={t('filter.by_day')}
          >
            <option value="all">{t('filter.any_day')}</option>
            {DAY_KEYS.map((d) => (
              <option key={d} value={d}>{dayLabelFor(d, locale)}</option>
            ))}
          </select>
          <ExportCsvButton onExport={exportCsv} />
          <button onClick={() => setCreating(true)}>{t('page.volunteers.new')}</button>
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.volunteer_application')} />
      <Table<AdminVolunteerApp>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(a) => a.id}
        loading={loading}
        empty={t('empty.volunteers')}
        selectable={sel.forRows(resp?.items ?? [])}
        rowProps={(a) => ({
          className: [
            highlight.isHighlighted(a.id) ? 'is-highlighted' : '',
            stripeForStatus(a.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(a.id),
        })}
      />
      <Pagination page={page} totalPages={resp?.total_pages ?? 1} onPageChange={setPage} disabled={loading} />
      <BulkBar
        count={sel.count}
        allowed={EDITABLE_STATUSES}
        onApply={applyBulkStatus}
        onDelete={applyBulkDelete}
        onClear={sel.clear}
        noun="applications"
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.volunteer_application'), id: deleting.id }) : ''}
        message={deleting ? t('common.confirm_delete_body', { name: deleting.full_name }) : ''}
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
      <EditModal
        open={modalOpen}
        mode={creating ? 'create' : 'edit'}
        title={creating ? t('common.modal_new', { noun: t('noun.volunteer_application') }) : editing ? t('common.modal_edit', { noun: t('noun.volunteer_application'), id: editing.id }) : ''}
        // Phase 26 — skill_tags arrives as string[]; the modal renders it
        // in a single text input, so we pre-join into a CSV string.
        // normalizeVolunteerPayload undoes this on save.
        initial={
          creating
            ? {}
            : {
                ...(editing as unknown as Record<string, unknown>),
                skill_tags: (editing?.skill_tags ?? []).join(', '),
              }
        }
        fields={creating ? VOLUNTEER_CREATE_FIELDS : VOLUNTEER_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
    </div>
  )
}

// === Mission signups tab (Phase 21) ==========================================
// One row per (volunteer × mission) join request. Admin actions per row:
//   pending              → [Approve] [Reject]
//   approved             → [Mark attended] [Cancel]
//   joined               → [Mark completed] [Mark no-show]
//   completion_requested → [Confirm completed] [Mark no-show]
//   completed / rejected / cancelled / no_show → no further action (read-only)

const SIGNUP_STATUSES = [
  'all', 'pending', 'approved', 'rejected', 'joined',
  'completion_requested', 'cancelled', 'completed', 'no_show',
] as const

const SIGNUP_CSV_COLUMNS: CsvColumn<AdminMissionSignup>[] = [
  { header: 'id', get: (s) => s.id },
  { header: 'user_id', get: (s) => s.user_id },
  { header: 'volunteer', get: (s) => s.user_full_name ?? '' },
  { header: 'phone', get: (s) => s.user_phone ?? '' },
  { header: 'mission_id', get: (s) => s.mission_id },
  { header: 'mission', get: (s) => s.mission_title },
  { header: 'mission_date', get: (s) => s.mission_date ?? '' },
  { header: 'city', get: (s) => s.mission_city ?? '' },
  { header: 'status', get: (s) => s.status },
  { header: 'hours_served', get: (s) => s.hours_served },
  { header: 'checked_in_at', get: (s) => s.checked_in_at ?? '' },
  { header: 'completed_at', get: (s) => s.completed_at ?? '' },
]

function MissionSignupsTab() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState<string>('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminMissionSignup> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const highlight = useHighlightedRow()
  const { refresh: refreshPendingCounts } = usePendingCounts()

  // Polling-like reload: 1) on tab mount, 2) when filters change, 3) after
  // any status action via setRefreshTick.
  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<AdminMissionSignup>>('/api/admin/volunteer_mission_signups', {
        params: {
          page,
          per_page: 20,
          status: status === 'all' ? undefined : status,
          q: q || undefined,
        },
      })
      .then((res) => { if (!cancelled) setResp(res.data) })
      .catch((e) => { if (!cancelled && !pollSilent.current) setErr(describeError(e)) })
      .finally(() => { if (!cancelled && !pollSilent.current) setLoading(false); pollSilent.current = false })
    return () => { cancelled = true }
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh mission signups every 5s. Volunteer
  // joins should surface to admin so they can approve in real time.
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 5_000)

  // Single helper for every status action (approve / reject / joined /
  // completed / cancelled / no_show). The backend fires the corresponding
  // 4-language notification automatically.
  const applyStatus = useCallback(
    async (id: number, newStatus: string) => {
      try {
        await api.post(`/api/admin/volunteer_mission_signups/${id}/status`, { status: newStatus })
        toast.success(t('toast.status_change', { noun: `${t('noun.mission_signup')} #${id}`, status: statusLabel(newStatus) }))
        setRefreshTick((t) => t + 1)
        // Decrement sidebar pending count immediately if we just resolved one.
        refreshPendingCounts()
      } catch (e) {
        toast.error(describeError(e))
      }
    },
    [toast, refreshPendingCounts],
  )

  const exportCsv = () => {
    const rows = resp?.items ?? []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`mission-signups-${new Date().toISOString().slice(0, 10)}.csv`, rows, SIGNUP_CSV_COLUMNS)
  }

  // The action buttons rendered depend on the current row status — the
  // map below mirrors the schema's allowed transitions to keep admin
  // from accidentally jumping a row from 'pending' directly to 'completed'.
  function actionsFor(s: AdminMissionSignup): { label: string; status: string; tone?: 'danger' }[] {
    switch (s.status) {
      case 'pending':
        return [
          { label: t('action.approve'), status: 'approved' },
          { label: t('action.reject'),  status: 'rejected', tone: 'danger' },
        ]
      case 'approved':
        return [
          { label: t('action.mark_attended'), status: 'joined' },
          { label: t('common.cancel'), status: 'cancelled', tone: 'danger' },
        ]
      case 'joined':
        return [
          { label: t('action.mark_completed'), status: 'completed' },
          { label: t('action.mark_no_show'), status: 'no_show', tone: 'danger' },
        ]
      case 'completion_requested':
        return [
          { label: t('action.confirm_completed'), status: 'completed' },
          { label: t('action.mark_no_show'), status: 'no_show', tone: 'danger' },
        ]
      // Terminal states are no longer a dead end: offer an Undo that reverts to
      // a sensible prior state, so an entry is never button-less / permanently
      // locked (the status dropdown also stays available for full control).
      case 'completed':
      case 'no_show':
        return [{ label: t('action.undo'), status: 'joined' }]
      case 'rejected':
        return [{ label: t('action.undo'), status: 'pending' }]
      case 'cancelled':
        return [{ label: t('action.undo'), status: 'approved' }]
      default:
        return []
    }
  }

  const columns: Column<AdminMissionSignup>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (s) => <strong>#{s.id}</strong> },
    {
      key: 'volunteer',
      header: t('col.volunteer'),
      cell: (s) => (
        <div className="cell-stack">
          <strong>{s.user_full_name ?? t('common.user_ref_lc', { id: s.user_id })}</strong>
          <span className="muted">{s.user_phone ?? '—'}</span>
        </div>
      ),
    },
    {
      key: 'mission',
      header: t('col.mission'),
      cell: (s) => (
        <div className="cell-stack">
          <Link to={`/detail/volunteer_missions/${s.mission_id}`} className="row-edit-btn">
            {s.mission_title}
          </Link>
          <span className="muted">
            {[s.mission_city, s.mission_date].filter(Boolean).join(' · ') || '—'}
          </span>
        </div>
      ),
    },
    {
      key: 'status',
      header: t('col.status'),
      width: '180px',
      // Interactive dropdown — admin can change status inline without
      // opening a modal. Hits the same /status endpoint as the action
      // buttons below, so transitions stay consistent.
      cell: (s) => (
        <StatusCell
          value={s.status}
          allowed={
            SIGNUP_STATUSES.filter((x) => x !== 'all') as unknown as string[]
          }
          label={t('common.signup_status_label')}
          onSave={async (next) => {
            await api.post(`/api/admin/volunteer_mission_signups/${s.id}/status`, { status: next })
            setRefreshTick((t) => t + 1)
            refreshPendingCounts()
          }}
        />
      ),
    },
    {
      key: 'progress',
      header: t('col.progress'),
      cell: (s) => (
        <span className="muted" style={{ fontSize: 12, fontVariantNumeric: 'tabular-nums' }}>
          {s.checked_in_at && <>in: {s.checked_in_at.slice(0, 10)}<br /></>}
          {s.completed_at && <>done: {s.completed_at.slice(0, 10)}<br /></>}
          {s.hours_served !== '0.00' && s.hours_served !== '0' && <>{s.hours_served} h</>}
          {!s.checked_in_at && !s.completed_at && (s.hours_served === '0.00' || s.hours_served === '0') && '—'}
        </span>
      ),
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '270px',
      cell: (s) => {
        const acts = actionsFor(s)
        if (acts.length === 0) {
          return <span className="muted" style={{ fontSize: 12 }}>—</span>
        }
        return (
          <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
            {acts.map((a) => (
              <button
                key={a.status}
                className={a.tone === 'danger' ? 'row-delete-btn' : 'row-edit-btn'}
                onClick={() => applyStatus(s.id, a.status)}
              >
                {a.label}
              </button>
            ))}
          </div>
        )
      },
    },
  ]

  return (
    <div className="stack">
      <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
        <p className="muted" style={{ margin: 0 }}>
          {resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}
        </p>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1) }}
            placeholder={t('page.volunteers.signups_search_placeholder')}
            style={{ width: '240px' }}
          />
          <select
            value={status}
            onChange={(e) => { setStatus(e.target.value); setPage(1) }}
            style={{ width: 'auto' }}
          >
            {SIGNUP_STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton onExport={exportCsv} />
        </div>
      </div>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.mission_signup')} />
      <Table<AdminMissionSignup>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(s) => s.id}
        loading={loading}
        empty={t('empty.signups')}
        rowProps={(s) => ({
          className: [
            highlight.isHighlighted(s.id) ? 'is-highlighted' : '',
            stripeForStatus(s.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(s.id),
        })}
      />
      <Pagination
        page={page}
        totalPages={resp?.total_pages ?? 1}
        onPageChange={setPage}
        disabled={loading}
      />
    </div>
  )
}
