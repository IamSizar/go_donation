// VolunteerBoardPage — Phase 24 — per-mission Kanban view of volunteer signups.
//
// One section per mission, four lanes inside each:
//   PENDING            — admin must approve / reject
//   APPROVED           — admin OK'd but volunteer hasn't shown up yet
//   ON MISSION         — joined + completion_requested (actively volunteering)
//   COMPLETED (30d)    — finished in the last 30 days
//
// Each card has the volunteer's name + phone + a "state-appropriate" action
// pair (e.g. pending → Approve/Reject ; joined → Mark completed/No-show).
// Status transitions hit the same POST /admin/volunteer_mission_signups/:id/status
// endpoint the Mission signups tab uses — fires the 4-language notification
// + bumps the sidebar pending count.
//
// Auto-refreshes every 10 seconds so the board stays current without a
// manual reload. Combined with the live-events feed on the dashboard,
// admin gets near-real-time visibility into what their volunteers are doing.

import { useCallback, useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import type { AdminBoardMission, AdminBoardSignup, AdminVolunteerBoard } from '../lib/api-types'
import { useToast } from '../lib/toast'
import { usePendingCounts } from '../lib/pendingCounts'
import { useI18n, useStatusLabel } from '../lib/i18n'
import ExportCsvButton from '../components/ExportCsvButton'
import { downloadCsv, type CsvColumn } from '../lib/csv'

const POLL_MS = 10_000

// The board is a Kanban of signups grouped by mission — the export flattens
// every signup (across all missions and lanes) into one row, carrying its
// mission context (Phase 7 · M-43).
type BoardExportRow = {
  mission_id: number
  mission_title: string
  mission_city: string
  mission_date: string
  signup_id: number
  user_id: number
  full_name: string
  phone: string
  status: string
  hours_served: string
  created_at: string
  completed_at: string
}
const BOARD_CSV_COLUMNS: CsvColumn<BoardExportRow>[] = [
  { header: 'mission_id', get: (r) => r.mission_id },
  { header: 'mission_title', get: (r) => r.mission_title },
  { header: 'mission_city', get: (r) => r.mission_city },
  { header: 'mission_date', get: (r) => r.mission_date },
  { header: 'signup_id', get: (r) => r.signup_id },
  { header: 'user_id', get: (r) => r.user_id },
  { header: 'full_name', get: (r) => r.full_name },
  { header: 'phone', get: (r) => r.phone },
  { header: 'status', get: (r) => r.status },
  { header: 'hours_served', get: (r) => r.hours_served },
  { header: 'created_at', get: (r) => r.created_at },
  { header: 'completed_at', get: (r) => r.completed_at },
]

function boardExportRows(board: AdminVolunteerBoard): BoardExportRow[] {
  const rows: BoardExportRow[] = []
  for (const m of board.missions) {
    const lanes = [m.lanes.pending, m.lanes.approved, m.lanes.on_mission, m.lanes.completed]
    for (const lane of lanes) {
      for (const s of lane) {
        rows.push({
          mission_id: m.id,
          mission_title: m.title,
          mission_city: m.city ?? '',
          mission_date: m.mission_date ?? '',
          signup_id: s.id,
          user_id: s.user_id,
          full_name: s.full_name ?? '',
          phone: s.phone ?? '',
          status: s.status,
          hours_served: s.hours_served,
          created_at: s.created_at,
          completed_at: s.completed_at ?? '',
        })
      }
    }
  }
  return rows
}

// Display config per lane — title, count chip color, allowed quick-actions
// per card. Keeping it as a single config table makes adding a new lane
// trivial (add to the type + add a row here).
type Lane = 'pending' | 'approved' | 'on_mission' | 'completed'
// Titles/subtitles are resolved via t('board.lane_<lane>' / 'board.sub_<lane>').
const LANE_META: Record<Lane, { tone: 'amber' | 'blue' | 'info' | 'green' }> = {
  pending:    { tone: 'amber' },
  approved:   { tone: 'blue' },
  on_mission: { tone: 'info' },
  completed:  { tone: 'green' },
}

// Per-status quick actions a card can offer. Mirrors the same allowed
// transitions enforced by the backend in admin_status.go. `labelKey` is
// resolved with t() at render time.
type QuickAction = { labelKey: string; status: string; tone?: 'danger' }
function actionsFor(s: AdminBoardSignup): QuickAction[] {
  switch (s.status) {
    case 'pending':
      return [{ labelKey: 'action.approve', status: 'approved' }, { labelKey: 'action.reject', status: 'rejected', tone: 'danger' }]
    case 'approved':
      return [{ labelKey: 'action.mark_attended', status: 'joined' }, { labelKey: 'common.cancel', status: 'cancelled', tone: 'danger' }]
    case 'joined':
      return [{ labelKey: 'action.mark_completed', status: 'completed' }, { labelKey: 'action.no_show', status: 'no_show', tone: 'danger' }]
    case 'completion_requested':
      return [{ labelKey: 'action.confirm_completed', status: 'completed' }, { labelKey: 'action.no_show', status: 'no_show', tone: 'danger' }]
    case 'completed':
      // Terminal state — no actions but show hours-served / completion date.
      return []
  }
}

// formatRelative — "2 hours ago" / "yesterday" / "3 days ago" for the card
// timestamp. Falls back to the ISO date when older than ~14 days.
type TFn = (key: string, vars?: Record<string, string | number>) => string
function formatRelative(iso: string | null, t: TFn): string {
  if (!iso) return ''
  const parsed = Date.parse(iso)
  if (isNaN(parsed)) return ''
  const diff = Date.now() - parsed
  const mins = Math.round(diff / 60_000)
  if (mins < 1) return t('board.just_now')
  if (mins < 60) return t('board.mins_ago', { n: mins })
  const hrs = Math.round(mins / 60)
  if (hrs < 24) return t('board.hours_ago', { n: hrs })
  const days = Math.round(hrs / 24)
  if (days <= 14) return t('board.days_ago', { n: days })
  return iso.slice(0, 10)
}

export default function VolunteerBoardPage() {
  const [data, setData] = useState<AdminVolunteerBoard | null>(null)
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const toast = useToast()
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const { refresh: refreshPendingCounts } = usePendingCounts()

  const exportCsv = () => {
    const rows = data ? boardExportRows(data) : []
    if (rows.length === 0) { toast.info(t('common.nothing_to_export')); return }
    downloadCsv(`volunteer-board-${new Date().toISOString().slice(0, 10)}.csv`, rows, BOARD_CSV_COLUMNS)
  }

  // Fetch once on mount + then on a 10s poll so the board stays fresh.
  // Same pattern as PendingCountsProvider — uses an AbortController to
  // cancel in-flight requests when a new one fires.
  const fetchBoard = useCallback(async (signal?: AbortSignal) => {
    try {
      const res = await api.get<AdminVolunteerBoard>('/api/admin/volunteer_board', { signal })
      setData(res.data)
      setErr(null)
    } catch (e: unknown) {
      const ex = e as { name?: string; code?: string }
      if (ex?.name === 'CanceledError' || ex?.code === 'ERR_CANCELED') return
      setErr(describeError(e))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    const ac = new AbortController()
    void fetchBoard(ac.signal)
    const id = window.setInterval(() => fetchBoard(), POLL_MS)
    return () => {
      ac.abort()
      window.clearInterval(id)
    }
  }, [fetchBoard])

  // Status transition handler — used by every quick-action button on every
  // card. Fires the backend update, then refetches the board so the card
  // moves to the right lane immediately.
  const applyStatus = useCallback(
    async (signupID: number, newStatus: string) => {
      try {
        await api.post(`/api/admin/volunteer_mission_signups/${signupID}/status`, { status: newStatus })
        toast.success(t('toast.status_change', { noun: `${t('noun.mission_signup')} #${signupID}`, status: statusLabel(newStatus) }))
        refreshPendingCounts()
        void fetchBoard()
      } catch (e) {
        toast.error(describeError(e))
      }
    },
    [toast, refreshPendingCounts, fetchBoard],
  )

  if (loading && !data) {
    return <div className="stack"><div className="muted">{t('board.loading')}</div></div>
  }
  if (err) {
    return <div className="stack"><div className="error-box">{err}</div></div>
  }
  if (!data) return null

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('board.title')}</h1>
          <p className="muted">
            {t('board.subtitle', { count: data.totals.missions })}
          </p>
        </div>
        {/* Totals across all missions — chips matching lane tones below. */}
        <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
          <span className="board-total board-total-amber">⏳ {t('board.total_pending', { n: data.totals.pending })}</span>
          <span className="board-total board-total-blue">📋 {t('board.total_approved', { n: data.totals.approved })}</span>
          <span className="board-total board-total-info">🛠 {t('board.total_on_mission', { n: data.totals.on_mission })}</span>
          <span className="board-total board-total-green">✓ {t('board.total_completed', { n: data.totals.completed })}</span>
          <ExportCsvButton onExport={exportCsv} />
        </div>
      </div>

      {data.missions.length === 0 ? (
        <div className="card" style={{ padding: 32, textAlign: 'center' }}>
          <p className="muted">{t('board.empty')}</p>
        </div>
      ) : (
        data.missions.map((m) => (
          <MissionRow key={m.id} mission={m} onAction={applyStatus} />
        ))
      )}
    </div>
  )
}

// MissionRow — one mission, four lanes, optionally collapsible header.
function MissionRow({
  mission,
  onAction,
}: {
  mission: AdminBoardMission
  onAction: (signupID: number, status: string) => void
}) {
  const statusLabel = useStatusLabel()
  const needed = mission.needed_volunteers
  const acceptedTotal = mission.counts.approved + mission.counts.on_mission + mission.counts.completed
  const progress = needed ? `${acceptedTotal} / ${needed}` : `${acceptedTotal}`

  return (
    <div className="board-mission">
      {/* Mission header — title, when/where, accept ratio, status badge */}
      <div className="board-mission-head">
        <div className="cell-stack">
          <strong style={{ fontSize: 15 }}>{mission.title}</strong>
          <span className="muted">
            {[mission.city, mission.mission_date].filter(Boolean).join(' · ') || '—'}
          </span>
        </div>
        <div className="row" style={{ gap: 8, alignItems: 'center' }}>
          <span className={`badge tone-${mission.status === 'open' ? 'success' : mission.status === 'completed' ? 'info' : 'warning'}`}>
            {statusLabel(mission.status)}
          </span>
          <span className="muted" style={{ fontSize: 13, fontVariantNumeric: 'tabular-nums' }}>
            👥 {progress}
          </span>
        </div>
      </div>

      {/* Four lanes side-by-side */}
      <div className="board-lanes">
        {(['pending', 'approved', 'on_mission', 'completed'] as Lane[]).map((lane) => (
          <BoardLane
            key={lane}
            lane={lane}
            cards={mission.lanes[lane]}
            count={mission.counts[lane]}
            onAction={onAction}
          />
        ))}
      </div>
    </div>
  )
}

// BoardLane — one column inside a mission row.
function BoardLane({
  lane,
  cards,
  count,
  onAction,
}: {
  lane: Lane
  cards: AdminBoardSignup[]
  count: number
  onAction: (signupID: number, status: string) => void
}) {
  const meta = LANE_META[lane]
  const { t } = useI18n()
  return (
    <div className={`board-lane board-lane-${meta.tone}`}>
      <div className="board-lane-head">
        <strong>{t(`board.lane_${lane}`)}</strong>
        <span className={`board-lane-count board-lane-count-${meta.tone}`}>{count}</span>
      </div>
      <span className="board-lane-sub muted">{t(`board.sub_${lane}`)}</span>
      <div className="board-lane-cards">
        {cards.length === 0 ? (
          <div className="board-lane-empty muted">—</div>
        ) : (
          cards.map((c) => <SignupCard key={c.id} signup={c} onAction={onAction} />)
        )}
      </div>
    </div>
  )
}

// SignupCard — a single volunteer's card. Shows name + phone + state-
// specific metadata (when they joined / checked in / completed) and the
// state-appropriate quick-action buttons.
function SignupCard({
  signup,
  onAction,
}: {
  signup: AdminBoardSignup
  onAction: (signupID: number, status: string) => void
}) {
  const actions = actionsFor(signup)
  const { t } = useI18n()
  // Pick the most relevant timestamp to surface per state.
  const meta =
    signup.status === 'pending'  ? t('board.joined_queue', { when: formatRelative(signup.created_at, t) }) :
    signup.status === 'approved' ? t('board.meta_approved')
                                 + (signup.notes ? ` · "${signup.notes.slice(0, 40)}"` : '') :
    signup.status === 'joined'                ? t('board.attended', { when: formatRelative(signup.checked_in_at, t) }) :
    signup.status === 'completion_requested'  ? t('board.claims_completion') :
    signup.status === 'completed'             ? t('board.done', { when: formatRelative(signup.completed_at, t) })
                                              + (signup.hours_served !== '0.00' && signup.hours_served !== '0'
                                                ? t('board.hours_served', { h: signup.hours_served }) : '') :
    ''

  const initials = (signup.full_name?.trim()?.split(/\s+/).map((p) => p[0]).slice(0, 2).join('') || '?').toUpperCase()

  return (
    <div className="board-card">
      <div className="board-card-head">
        <span className="board-card-avatar" aria-hidden="true">{initials}</span>
        <div className="cell-stack" style={{ minWidth: 0 }}>
          <strong>{signup.full_name?.trim() || t('common.user_ref_lc', { id: signup.user_id })}</strong>
          <span className="muted" style={{ fontSize: 11 }}>{signup.phone ?? '—'}</span>
        </div>
      </div>
      <span className="board-card-meta muted">{meta}</span>
      {actions.length > 0 && (
        <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {actions.map((a) => (
            <button
              key={a.status}
              className={a.tone === 'danger' ? 'row-delete-btn' : 'row-edit-btn'}
              onClick={() => onAction(signup.id, a.status)}
              style={{ fontSize: 11, padding: '3px 8px' }}
            >
              {t(a.labelKey)}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
