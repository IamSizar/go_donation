// MissionsPage — admin page for volunteer_missions CRUD (Phase 22).
//
// Pattern mirrors CampaignsPage:
//   • Top: search + status filter + Export CSV + New mission
//   • Table: id, multilingual title, city/date, signup progress, status, actions
//   • Per-row: View / Edit / Delete + status dropdown for quick state changes
//   • Create + edit go through EditModal with the same 4-language field set
//
// Behavior glue:
//   • Creating with status='open' triggers the backend broadcast to all
//     volunteers (NewVolunteerMissionMsg in 4 languages). Drafts don't.
//   • Status change to 'open' (from draft / closed) also triggers broadcast.
//   • Delete CASCADEs signups — confirm dialog spells this out.

import { useCallback, useEffect, useState, useRef } from 'react'
import ActionsMenu from '../components/ActionsMenu'
import ExportCsvButton from '../components/ExportCsvButton'
import { api, describeError } from '../lib/api'
import { useLivePoll } from '../lib/useLivePoll'
import type { AdminMission, AdminPageResp } from '../lib/api-types'
import Table, { type Column } from '../components/Table'
import Pagination from '../components/Pagination'
import StatusCell from '../components/StatusCell'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ConfirmDialog from '../components/ConfirmDialog'
import { useToast } from '../lib/toast'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useSelection } from '../lib/useSelection'
import { type CsvColumn } from '../lib/csv'
import { HighlightBanner, useHighlightedRow } from '../lib/useHighlightedRow'
import { stripeForStatus } from '../lib/statusColors'
import PageHead from '../components/PageHead'
import { fmtId } from '../lib/formatId'

const PER_PAGE = 20
const STATUSES = ['all', 'draft', 'open', 'closed', 'completed', 'cancelled'] as const
const EDITABLE_STATUSES = STATUSES.filter((s) => s !== 'all')

// Field set used in BOTH the create modal and the edit modal. Status
// defaults to 'open' on create (set via `initial` below) so the common
// case (new mission, immediately visible) needs zero clicks.
const MISSION_FIELDS: FieldSpec[] = [
  {
    key: 'status',
    label: 'Status', labelKey: 'field.status',
    type: 'select',
    options: EDITABLE_STATUSES as unknown as string[],
    required: true,
  },
  { key: 'title',              label: 'Title (EN)', labelKey: 'field.title_en',          type: 'text',     required: true },
  { key: 'title_ar',           label: 'Title (AR)', labelKey: 'field.title_ar',          type: 'text',     dir: 'rtl' },
  { key: 'title_sorani',       label: 'Title (Sorani)', labelKey: 'field.title_sorani',      type: 'text',     dir: 'rtl' },
  { key: 'title_badini',       label: 'Title (Badini)', labelKey: 'field.title_badini',      type: 'text',     dir: 'rtl' },
  // F7 — "change their sections". Free text so staff can name a section
  // without an admin first creating one; empty means unsectioned.
  { key: 'section',            label: 'Section', labelKey: 'field.section',          type: 'text',     placeholder: 'e.g. Field work', placeholderKey: 'hint.eg_section' },
  { key: 'city',               label: 'City', labelKey: 'field.city',                type: 'text',     placeholder: 'e.g. Erbil', placeholderKey: 'hint.eg_city' },
  { key: 'mission_date',       label: 'Mission date', labelKey: 'field.mission_date',        type: 'text',     placeholder: 'YYYY-MM-DD' },
  { key: 'needed_volunteers',  label: 'Needed volunteers', labelKey: 'field.needed_volunteers',   type: 'number',   placeholder: 'e.g. 10', placeholderKey: 'hint.eg_volunteer_count' },
  { key: 'description',        label: 'Description (EN)', labelKey: 'field.description_en',    type: 'textarea', rows: 3 },
  { key: 'description_ar',     label: 'Description (AR)', labelKey: 'field.description_ar',    type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_sorani', label: 'Description (Sorani)', labelKey: 'field.description_sorani',type: 'textarea', rows: 3, dir: 'rtl' },
  { key: 'description_badini', label: 'Description (Badini)', labelKey: 'field.description_badini',type: 'textarea', rows: 3, dir: 'rtl' },
]

const CSV_COLUMNS: CsvColumn<AdminMission>[] = [
  { header: 'id', get: (m) => m.id },
  { header: 'title', get: (m) => m.title },
  { header: 'title_ar', get: (m) => m.title_ar },
  { header: 'section', get: (m) => m.section },
  { header: 'city', get: (m) => m.city },
  { header: 'mission_date', get: (m) => m.mission_date },
  { header: 'needed_volunteers', get: (m) => m.needed_volunteers },
  { header: 'status', get: (m) => m.status },
  { header: 'accepted_volunteers', get: (m) => m.accepted_volunteers },
  { header: 'pending_volunteers', get: (m) => m.pending_volunteers },
]

// progressLabel renders "5 / 8" when needed_volunteers is set, else just "5".
// Pads with the pending count in subtle gray when there are pending requests
// the admin hasn't acted on yet.
type TFn = (key: string, vars?: Record<string, string | number>) => string
function progressLabel(m: AdminMission, t: TFn): { accepted: string; pending: string } {
  const needed = m.needed_volunteers ?? null
  return {
    accepted: needed ? `${m.accepted_volunteers} / ${needed}` : String(m.accepted_volunteers),
    pending: m.pending_volunteers > 0 ? t('page.missions.pending_badge', { n: m.pending_volunteers }) : '',
  }
}

export default function MissionsPage() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState<string>('all')
  const [q, setQ] = useState('')
  const [resp, setResp] = useState<AdminPageResp<AdminMission> | null>(null)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [editing, setEditing] = useState<AdminMission | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<AdminMission | null>(null)
  const [refreshTick, setRefreshTick] = useState(0)
  // F7 — true while a reorder POST is in flight, so the arrows disable and two
  // fast clicks cannot race each other into an order neither click asked for.
  const [reordering, setReordering] = useState(false)
  // Phase 27.9 — true while a background poll is refetching, so the loader
  // stays hidden and the list updates silently (no full reload flash).
  const pollSilent = useRef(false)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const sel = useSelection<AdminMission>((m) => m.id)
  const highlight = useHighlightedRow()

  useEffect(() => {
    let cancelled = false
    if (!pollSilent.current) { setLoading(true); setErr(null) }
    api
      .get<AdminPageResp<AdminMission>>('/api/admin/missions', {
        params: { page, per_page: PER_PAGE, status: status === 'all' ? undefined : status, q: q || undefined },
      })
      .then((res) => { if (!cancelled) setResp(res.data) })
      .catch((e) => { if (!cancelled && !pollSilent.current) setErr(describeError(e)) })
      .finally(() => { if (!cancelled && !pollSilent.current) setLoading(false); pollSilent.current = false })
    return () => { cancelled = true }
  }, [page, status, q, refreshTick])

  // Phase 27 — live refresh missions every 10s (medium cadence; new
  // mission creation isn't urgent, but volunteer signup counts moving
  // is useful to see live).
  useLivePoll(() => { pollSilent.current = true; setRefreshTick((t) => t + 1) }, 10_000)

  // F7 — the rows as currently displayed. The reorder POST sends the ids of
  // THIS page in their new order, and the backend numbers them from 1.
  const items = resp?.items ?? []

  // move swaps a mission with its neighbour and persists the new order.
  //
  // Optimistic: the row moves immediately and only rolls back if the server
  // refuses, because waiting on a round-trip to see an arrow take effect makes
  // reordering a long list feel broken. A refused reorder is atomic on the
  // server (nothing moved), so refetching restores the true order exactly.
  const move = useCallback(
    async (index: number, dir: -1 | 1) => {
      const next = index + dir
      if (index < 0 || next < 0 || next >= items.length) return
      const reordered = [...items]
      const [row] = reordered.splice(index, 1)
      reordered.splice(next, 0, row)
      const previous = resp
      setResp((r) => (r ? { ...r, items: reordered } : r))
      setReordering(true)
      try {
        await api.post('/api/admin/missions/reorder', { ids: reordered.map((x) => x.id) })
        // Refetch rather than trust the optimistic list: another admin may
        // have changed the same page, and the server is the authority on order.
        setRefreshTick((t) => t + 1)
      } catch (e) {
        setResp(previous)
        toast.error(describeError(e))
      } finally {
        setReordering(false)
      }
    },
    [items, resp, toast],
  )

  const handleSave = useCallback(
    async (id: number, patch: Record<string, unknown>) => {
      await api.patch(`/api/admin/missions/${id}`, normalizeMissionPatch(patch))
      toast.success(t('toast.saved', { noun: `${t('noun.mission')} #${id}` }))
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleCreate = useCallback(
    async (data: Record<string, unknown>) => {
      const res = await api.post<{ id: number; status: string }>(
        '/api/admin/missions',
        normalizeMissionPatch(data),
      )
      // When admin creates an OPEN mission, the backend broadcasts to all
      // volunteers — surface that in the success toast so the admin
      // knows it just went out.
      const sentNotice = res.data.status === 'open' ? t('page.missions.broadcast_sent') : ''
      toast.success(t('toast.created', { noun: `${t('noun.mission')} #${res.data.id}` }) + sentNotice)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  const handleDelete = useCallback(
    async (id: number) => {
      await api.delete(`/api/admin/missions/${id}`)
      toast.success(t('toast.deleted', { noun: `${t('noun.mission')} #${id}` }))
      setDeleting(null)
      setRefreshTick((t) => t + 1)
    },
    [toast],
  )

  // Quick-status change without opening the full edit modal — useful for
  // "open this draft" or "close this mission" workflows.
  const handleQuickStatus = useCallback(
    async (id: number, newStatus: string) => {
      try {
        await api.post(`/api/admin/missions/${id}/status`, { status: newStatus })
        const broadcastNote = newStatus === 'open' ? t('page.missions.broadcast_sent') : ''
        toast.success(t('toast.status_change', { noun: `${t('noun.mission')} #${id}`, status: statusLabel(newStatus) }) + broadcastNote)
        setRefreshTick((t) => t + 1)
      } catch (e) {
        toast.error(describeError(e))
      }
    },
    [toast],
  )


  const modalOpen = editing !== null || creating
  const closeModal = () => { setEditing(null); setCreating(false) }

  const columns: Column<AdminMission>[] = [
    { key: 'id', header: t('col.id'), width: '60px', cell: (m) => <strong>{fmtId(m.id)}</strong> },
    {
      key: 'title',
      header: t('col.mission'),
      cell: (m) => (
        <div className="cell-stack">
          <strong>{m.title}</strong>
          {m.title_ar && <span className="muted">{m.title_ar}</span>}
          {/* F7 — the section is shown on the row rather than in a separate
              column, so the list stays readable at this width and an
              unsectioned mission simply shows nothing extra. */}
          {m.section && <span className="muted" style={{ fontSize: 11 }}>{m.section}</span>}
        </div>
      ),
    },
    {
      // F7 — reorder. Arrows rather than drag-and-drop: they work with a
      // keyboard and a screen reader, and they are unambiguous in RTL, where
      // a dragged row's direction is a guess. Disabled at the ends, and
      // disabled entirely while a reorder is in flight so two quick clicks
      // cannot race each other into a wrong order.
      key: 'order',
      header: t('col.sort_order'),
      width: '92px',
      cell: (m) => {
        const i = items.findIndex((x) => x.id === m.id)
        return (
          <div style={{ display: 'flex', gap: 4 }}>
            <button
              className="btn"
              title={t('common.move_up')}
              aria-label={t('common.move_up')}
              disabled={reordering || i <= 0}
              onClick={() => move(i, -1)}
            >↑</button>
            <button
              className="btn"
              title={t('common.move_down')}
              aria-label={t('common.move_down')}
              disabled={reordering || i < 0 || i >= items.length - 1}
              onClick={() => move(i, 1)}
            >↓</button>
          </div>
        )
      },
    },
    {
      key: 'when_where',
      header: t('col.when_where'),
      cell: (m) => (
        <div className="cell-stack">
          <span>{m.mission_date ?? '—'}</span>
          <span className="muted">{m.city ?? '—'}</span>
        </div>
      ),
    },
    {
      key: 'volunteers',
      header: t('col.volunteers'),
      align: 'right',
      cell: (m) => {
        const p = progressLabel(m, t)
        return (
          <div className="cell-stack" style={{ alignItems: 'flex-end' }}>
            <strong>{p.accepted}</strong>
            {p.pending && <span className="muted" style={{ fontSize: 11 }}>{p.pending}</span>}
          </div>
        )
      },
    },
    {
      key: 'status',
      header: t('col.status'),
      width: '170px',
      cell: (m) => (
        // Inline status editor — admin can change status via the dropdown
        // without opening the edit modal. Same backend endpoint the quick-
        // action buttons below the table use, so transitions are consistent
        // regardless of which control admin picks.
        <StatusCell
          value={m.status}
          allowed={EDITABLE_STATUSES as unknown as string[]}
          label={t('common.mission_status_label')}
          onSave={async (next) => {
            await api.post(`/api/admin/missions/${m.id}/status`, { status: next })
            setRefreshTick((t) => t + 1)
          }}
        />
      ),
    },
    {
      key: 'actions',
      header: t('common.actions'),
      width: '110px',
      cell: (m) => {
        // Note #21 — this used to render a different set of loose inline
        // buttons per status (draft → "Open"; open → "Close"+"Mark
        // completed"; etc.), so the cell's width/height changed the instant
        // a row's status changed, visibly distorting the table. A single
        // fixed-footprint dropdown (same pattern as Users' row actions)
        // keeps the trigger identical regardless of status — only the
        // portaled menu panel varies, and that never affects table layout.
        const items = [
          { key: 'view', label: t('common.view'), href: `/detail/volunteer_missions/${m.id}`, onClick: () => {} },
          { key: 'edit', label: t('common.edit'), onClick: () => setEditing(m) },
          ...(m.status === 'draft'
            ? [{ key: 'open', label: t('action.open_mission'), onClick: () => handleQuickStatus(m.id, 'open') }]
            : []),
          ...(m.status === 'open'
            ? [{ key: 'close', label: t('action.close_mission'), onClick: () => handleQuickStatus(m.id, 'closed') }]
            : []),
          ...(m.status === 'closed' || m.status === 'open'
            ? [{ key: 'complete', label: t('action.mark_completed'), onClick: () => handleQuickStatus(m.id, 'completed') }]
            : []),
          ...(m.status === 'completed' || m.status === 'cancelled'
            ? [{ key: 'reopen', label: t('action.reopen'), onClick: () => handleQuickStatus(m.id, 'open') }]
            : []),
          { key: 'delete', label: t('common.delete'), danger: true, onClick: () => setDeleting(m) },
        ]
        return <ActionsMenu items={items} />
      },
    },
  ]

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('page.missions.title')}</h1>
          <p className="muted">
            {resp ? `${resp.total_items} ${t('common.total')}` : t('common.loading')}
          </p>
        </div>
        <div className="row">
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(1); sel.clear() }}
            placeholder={t('page.missions.search_placeholder')}
            style={{ width: '220px' }}
          />
          <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1); sel.clear() }} style={{ width: 'auto' }}>
            {STATUSES.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
          </select>
          <ExportCsvButton
            rows={resp?.items ?? []}
            columns={CSV_COLUMNS}
            filenameBase="missions"
            title={t('nav.missions')}
            module="missions"
          />
          <button onClick={() => setCreating(true)}>{t('page.missions.new')}</button>
        </div>
      </PageHead>
      {err && <div className="error-box">{err}</div>}
      <HighlightBanner kind={t('noun.mission')} />
      <Table<AdminMission>
        rows={resp?.items ?? []}
        columns={columns}
        rowKey={(m) => m.id}
        loading={loading}
        empty={t('empty.missions')}
        rowProps={(m) => ({
          className: [
            highlight.isHighlighted(m.id) ? 'is-highlighted' : '',
            stripeForStatus(m.status),
          ].filter(Boolean).join(' '),
          'data-highlight-id': String(m.id),
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
        title={creating ? t('common.modal_new', { noun: t('noun.mission') }) : editing ? t('common.modal_edit', { noun: t('noun.mission'), id: editing.id }) : ''}
        // Pre-fill status='open' on create so admin doesn't have to pick it
        // every time. The "broadcast on open" behavior makes this an active
        // choice the admin can override by switching to 'draft'.
        initial={
          creating
            ? { status: 'open' }
            : editing
            ? (editing as unknown as Record<string, unknown>)
            : {}
        }
        fields={MISSION_FIELDS}
        onSave={(data) => (creating ? handleCreate(data) : handleSave(editing!.id, data))}
        onClose={closeModal}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={deleting ? t('common.confirm_delete_title', { noun: t('noun.mission'), id: deleting.id }) : ''}
        message={
          deleting
            ? `${t('common.confirm_delete_body', { name: deleting.title })} ${
                deleting.accepted_volunteers + deleting.pending_volunteers > 0
                  ? t('page.missions.cascade_warn', { n: deleting.accepted_volunteers + deleting.pending_volunteers })
                  : t('page.missions.no_signups')
              }`
            : ''
        }
        onConfirm={() => handleDelete(deleting!.id)}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}

// Normalize patch before sending to backend:
//   • needed_volunteers as number (EditModal stores it as string)
//   • mission_date trimmed; empty string → omitted (backend leaves NULL)
function normalizeMissionPatch(patch: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...patch }
  if (typeof out.needed_volunteers === 'string') {
    const n = parseInt(out.needed_volunteers as string, 10)
    out.needed_volunteers = isFinite(n) ? n : null
  }
  if (typeof out.mission_date === 'string' && (out.mission_date as string).trim() === '') {
    delete out.mission_date
  }
  return out
}
