/**
 * Employee profile — what one staff member has actually decided.
 *
 * THE ASK: "an employee profile created by the super admin, containing all of
 * his actions and activity and all the causes he handled and accepted."
 *
 * The dashboard could already answer "who are my staff?" (Staff) and "what
 * happened across the system?" (Audit Logs). Neither answers the question a
 * manager asks about a PERSON, which is why this page exists rather than
 * another filter on an existing list.
 *
 * Everything shown comes from the decision columns the app already writes —
 * see the package note on backend/internal/staffactivity. Nothing here is
 * derived, guessed or aggregated in the browser: the server does the counting,
 * so this page and any other reader of that endpoint cannot disagree.
 *
 * WHY "CURRENTLY ASSIGNED" IS A SEPARATE BLOCK, NOT TIMELINE ROWS
 * Chat assignment is current state with no claim timestamp. Dating those rows
 * would mean printing the thread's last-message time as if it were the moment
 * of claiming. They are shown as counts, under their own heading, labelled as
 * "now" rather than as history.
 */
import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'

import { api, describeError } from '../lib/api'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { formatDateTime } from '../lib/dates'
import { fmtId } from '../lib/formatId'
import { formatPhone } from '../lib/phone'
import PageHead from '../components/PageHead'
import StatCard from '../components/StatCard'

type Entry = {
  kind: 'case' | 'registration' | 'profile_change' | 'meeting_request' | 'permission'
  action: string
  subject: string
  entity_id: number
  at: string
}

type Profile = {
  user_id: number
  name: string
  phone: string
  staff_tier: string
  active: boolean
  joined_at: string | null
  totals: {
    cases_reviewed: number
    registrations_reviewed: number
    profile_changes_decided: number
    meeting_requests_decided: number
    permission_changes: number
    all: number
  }
  currently_assigned: { donor_chats: number; case_volunteer_chats: number }
  timeline: Entry[]
  timeline_truncated: boolean
}

/** Where a timeline row leads. Kinds with no dedicated screen get no link
 *  rather than a link that 404s — a dead link is worse than plain text. */
const DESTINATION: Partial<Record<Entry['kind'], (id: number) => string>> = {
  case: (id) => `/detail/beneficiary_cases/${id}`,
  registration: (id) => `/detail/users/${id}`,
}

export default function StaffActivityPage() {
  const { id = '' } = useParams<{ id: string }>()
  const { t } = useI18n()
  // The same status.* source the tables use, so 'approved' reads identically
  // here and on the page the row links to. Unknown values pass through raw
  // rather than rendering as a key.
  const statusLabel = useStatusLabel()
  const [profile, setProfile] = useState<Profile | null>(null)
  const [err, setErr] = useState<string | null>(null)
  // Which employee the state in this component belongs to. React reuses this
  // component when only the :id changes, so without the reset below the page
  // would show the PREVIOUS employee's decisions under the new one's name
  // until the fetch returned — the one mistake this feature must never make.
  // Adjusting state during render is React's documented way to do this; an
  // effect would render the wrong data for a frame first.
  const [shownFor, setShownFor] = useState(id)
  if (id !== shownFor) {
    setShownFor(id)
    setProfile(null)
    setErr(null)
  }
  // Derived, not stored: "nothing yet, and nothing went wrong" IS loading, and
  // a second flag can only disagree with the two that decide what renders.
  const loading = profile === null && err === null

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ profile: Profile }>(
        `/api/admin/staff/${id}/activity`,
      )
      setProfile(res.data.profile)
      setErr(null)
    } catch (e) {
      setErr(describeError(e))
    }
  }, [id])

  useEffect(() => {
    load()
  }, [load])

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1 style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ fontSize: '1.3rem' }}>🗂</span>
            {profile ? profile.name || t('common.user_ref', { id: profile.user_id }) : t('nav.staff')}
          </h1>
          <p className="muted">
            {profile
              ? `${statusLabel(profile.staff_tier)} · ${formatPhone(profile.phone)}`
              : t('common.loading')}
          </p>
        </div>
        <Link className="secondary" to="/staff" style={{ padding: '6px 12px' }}>
          {t('staff_activity.back')}
        </Link>
      </PageHead>

      {err && <div className="error-box">{err}</div>}
      {loading && !profile && <p className="muted">{t('common.loading')}</p>}

      {profile && (
        <>
          <div className="stat-grid">
            <StatCard
              label={t('staff_activity.cases')}
              value={profile.totals.cases_reviewed}
            />
            <StatCard
              label={t('staff_activity.registrations')}
              value={profile.totals.registrations_reviewed}
            />
            <StatCard
              label={t('staff_activity.profile_changes')}
              value={profile.totals.profile_changes_decided}
            />
            <StatCard
              label={t('staff_activity.meeting_requests')}
              value={profile.totals.meeting_requests_decided}
            />
            <StatCard
              label={t('staff_activity.permission_changes')}
              value={profile.totals.permission_changes}
            />
            <StatCard
              label={t('staff_activity.assigned_now')}
              value={
                profile.currently_assigned.donor_chats +
                profile.currently_assigned.case_volunteer_chats
              }
              hint={t('staff_activity.assigned_now_hint')}
            />
          </div>

          <div className="card stack">
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <h2 style={{ margin: 0, fontSize: 16 }}>{t('staff_activity.timeline')}</h2>
              <span className="muted" style={{ fontSize: 12.5 }}>
                {profile.timeline_truncated
                  ? t('staff_activity.showing_recent', {
                      n: profile.timeline.length,
                      total: profile.totals.all,
                    })
                  : t('staff_activity.showing_all', { n: profile.timeline.length })}
              </span>
            </div>

            {profile.timeline.length === 0 ? (
              // An empty state, not a blank card: "nothing recorded" is a real
              // and common answer for a new employee, and must not read as a
              // page that failed to load.
              <p className="muted" style={{ margin: 0 }}>
                {t('staff_activity.empty')}
              </p>
            ) : (
              <ul className="events-list" style={{ listStyle: 'none', margin: 0, padding: 0 }}>
                {profile.timeline.map((e) => {
                  const to = DESTINATION[e.kind]?.(e.entity_id)
                  const label = (
                    <>
                      <strong>{t(`staff_activity.kind.${e.kind}`)}</strong>
                      {' · '}
                      {statusLabel(e.action)}
                      {e.subject ? ` · ${e.subject}` : ''}
                    </>
                  )
                  return (
                    <li
                      key={`${e.kind}-${e.entity_id}-${e.at}`}
                      className="event-row"
                      style={{ justifyContent: 'space-between', gap: 12 }}
                    >
                      <span>
                        {to ? <Link to={to}>{label}</Link> : label}
                        <span className="muted"> {fmtId(e.entity_id)}</span>
                      </span>
                      <span className="muted" style={{ whiteSpace: 'nowrap', fontSize: 12.5 }}>
                        {formatDateTime(e.at)}
                      </span>
                    </li>
                  )
                })}
              </ul>
            )}
          </div>
        </>
      )}
    </div>
  )
}
