// Realtime events feed — listens on Firestore `events` collection and renders
// a sorted timeline with per-event icon + tone, sound notifications, and a
// toast/banner when new rows arrive. Filters: range (today / 7d / all),
// topic chips, free-text search, hide-read toggle.
//
// Mirrors the behavior of the old PHP admin's dashboard event panel.

import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { useGlobalAlerts } from '../lib/globalAlerts'
import { useI18n } from '../lib/i18n'

// Firestore `events` document shape — matches what the old PHP admin writes
// from the mobile app. Key field is `event_type` (NOT `type`); actor info is
// `name` + `number`; target/body info is in `module`, `action`, `note`,
// `event_label`.
type EventRow = {
  id: string
  event_type: string
  created_at_ms?: number
  created_at?: { toMillis?: () => number }
  name?: string
  number?: string
  user_id?: number | string
  // Mobile-side `AppEventFirestore.log` writes:
  //   entity_id  — the primary record this event created/touched
  //                (e.g. donation_id for donation_submit, ticket_id for support_ticket_submit)
  //   target_id  — a secondary reference (e.g. the campaign a donation went to)
  // We use entity_id first to deep-link the admin into the record's detail
  // page; target_id is a fallback when entity_id is absent.
  entity_id?: number | string
  target_id?: number | string
  module?: string
  action?: string
  note?: string
  event_label?: string
  admin_state?: string
  is_read?: boolean
  // Money-event extras the mobile app writes. donation_submit / sponsorship_submit
  // include `amount` and `currency`; the feed now uses them to render
  // "Donated 33,000 IQD to Medical Aid…" instead of the generic
  // "Donation submitted" body.
  amount?: number | string
  currency?: string
  metadata?: Record<string, unknown>
  [k: string]: unknown
}

// Pretty-prints 33000 → "33,000". Used in the event body. Mirrors the same
// formatter used in the donation-approved notification template so the two
// surfaces read consistently.
function formatAmount(n: number): string {
  if (!isFinite(n) || n <= 0) return ''
  const s = Math.round(n).toString()
  if (s.length <= 3) return s
  let out = ''
  for (let i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 === 0) out += ','
    out += s[i]
  }
  return out
}

// actorFor mirrors the old admin's helper — prefers "name · phone", falls
// through to bare name, phone, user id, or a generic label.
function actorFor(r: EventRow): string {
  const name = String(r.name ?? '').trim()
  const number = String(r.number ?? '').trim()
  if (name && number) return `${name} · ${number}`
  if (name) return name
  if (number) return number
  if (r.user_id) return `user #${r.user_id}`
  return 'App user'
}

// Try to resolve the campaign id this event references. donation_submit and
// sponsorship_submit both write the campaign as `target_id`, but older app
// versions stuffed it under metadata.campaign_id, so we probe both.
function campaignIdFor(r: EventRow): number | null {
  const direct = Number(r.target_id)
  if (Number.isFinite(direct) && direct > 0) return direct
  const meta = r.metadata as { campaign_id?: number | string } | undefined
  if (meta?.campaign_id != null) {
    const n = Number(meta.campaign_id)
    if (Number.isFinite(n) && n > 0) return n
  }
  return null
}

// bodyFor renders the most-informative description of the event.
//
// Phase 18d — for money events (donation_submit, sponsorship_submit) we now
// build a much richer body using the amount + currency + campaign title:
//   "Donated 33,000 IQD to Medical Aid for Cancer Patients"
// The `campaignMap` param maps campaign-id → human title (filled in once by
// EventsFeed on mount via /api/admin/campaigns). When a campaign id is
// unknown (e.g. an old admin-deleted campaign), we fall back gracefully.
//
// For all other event types we keep the original behavior: note → event_label
// → "module · action".
function bodyFor(
  r: EventRow,
  campaignMap: Record<number, string>,
  t: (key: string, vars?: Record<string, string | number>) => string,
): string {
  switch (r.event_type) {
    case 'donation_submit': {
      const amount = formatAmount(Number(r.amount))
      const currency = String(r.currency ?? 'IQD').trim() || 'IQD'
      const campaignId = campaignIdFor(r)
      const campaignTitle = campaignId ? campaignMap[campaignId] : ''
      if (amount && campaignTitle) return t('common.fd_donated_to', { amount, currency, title: campaignTitle })
      if (amount)                  return t('common.fd_donated', { amount, currency })
      if (campaignTitle)           return t('common.fd_donated_title', { title: campaignTitle })
      break
    }
    case 'sponsorship_submit': {
      const amount = formatAmount(Number(r.amount))
      const currency = String(r.currency ?? 'IQD').trim() || 'IQD'
      const campaignId = campaignIdFor(r)
      const campaignTitle = campaignId ? campaignMap[campaignId] : ''
      if (amount && campaignTitle) return t('common.fd_sponsor_to', { amount, currency, title: campaignTitle })
      if (amount)                  return t('common.fd_sponsor', { amount, currency })
      if (campaignTitle)           return t('common.fd_sponsor_title', { title: campaignTitle })
      break
    }
  }
  const note = String(r.note ?? '').trim()
  if (note) return note
  const label = String(r.event_label ?? '').trim()
  if (label) return label
  const mod = String(r.module ?? '').trim()
  const act = String(r.action ?? '').trim()
  if (mod && act) return `${mod} · ${act}`
  if (mod) return mod
  return '—'
}

type EventMeta = {
  icon: string
  tone: 'primary' | 'info' | 'success' | 'warning' | 'danger' | 'neutral'
  badge: string
  category: string
}

const EVENT_META: Record<string, EventMeta> = {
  login: { icon: '↪', tone: 'primary', badge: 'Login', category: 'Core' },
  register: { icon: '＋', tone: 'primary', badge: 'Register', category: 'Core' },
  role_select: { icon: '🪪', tone: 'primary', badge: 'Role', category: 'Core' },
  profile_update: { icon: '✎', tone: 'info', badge: 'Profile', category: 'People' },
  donation_submit: { icon: '$', tone: 'success', badge: 'Donation', category: 'Money' },
  sponsorship_submit: { icon: '♡', tone: 'success', badge: 'Sponsorship', category: 'Money' },
  sponsorship_cancel: { icon: '✕', tone: 'warning', badge: 'Sponsorship', category: 'Money' },
  beneficiary_case_submit: { icon: '⚕', tone: 'danger', badge: 'Case', category: 'Review' },
  project_request_submit: { icon: '🗂', tone: 'danger', badge: 'Project', category: 'Review' },
  marketplace_order_submit: { icon: '🛍', tone: 'warning', badge: 'Marketplace', category: 'Orders' },
  volunteer_application_submit: { icon: '👥', tone: 'info', badge: 'Volunteer', category: 'People' },
  volunteer_mission_join: { icon: '✓', tone: 'info', badge: 'Volunteer', category: 'People' },
  support_ticket_submit: { icon: '🛟', tone: 'danger', badge: 'Support', category: 'Review' },
  in_kind_donation_submit: { icon: '📦', tone: 'success', badge: 'In-kind', category: 'Money' },
  marriage_profile_submit: { icon: '💍', tone: 'info', badge: 'Marriage', category: 'People' },
  notification_mark_read: { icon: '🔕', tone: 'warning', badge: 'Notification', category: 'Orders' },
}

function metaFor(type: string): EventMeta {
  return EVENT_META[type] ?? { icon: '•', tone: 'neutral', badge: 'Event', category: 'Activity' }
}

// Map the English badge/category label to its i18n key so the chips localize.
const BADGE_KEY: Record<string, string> = {
  Login: 'bdg_login', Register: 'bdg_register', Role: 'bdg_role', Profile: 'bdg_profile',
  Donation: 'bdg_donation', Sponsorship: 'bdg_sponsorship', Case: 'bdg_case', Project: 'bdg_project',
  Marketplace: 'bdg_marketplace', Volunteer: 'bdg_volunteer', Support: 'bdg_support',
  'In-kind': 'bdg_inkind', Marriage: 'bdg_marriage', Notification: 'bdg_notification', Event: 'bdg_event',
}
const CAT_KEY: Record<string, string> = {
  Core: 'cat_core', People: 'cat_people', Money: 'cat_money', Review: 'cat_review',
  Orders: 'cat_orders', Activity: 'cat_activity',
}

// === Click-through routing for live events ===
// Each row in the feed represents something that happened in the mobile app.
// Clicking a row should take the admin straight to the page where they can
// REVIEW / APPROVE / RESPOND to that thing — e.g. a donation_submit jumps to
// the donation's detail page, project_request_submit jumps to the project
// request, support_ticket_submit jumps to the ticket.
//
// `resource` matches DetailPage's RESOURCE_LABELS keys (so we deep-link to
// /detail/<resource>/<id>). `list` is the fallback when we don't have an
// entity id to deep-link with (we still navigate the admin to the relevant
// page so they can find the row manually).
//
// `useUserId: true` is for identity events (login/register/role_select/
// profile_update) where the meaningful record is the user, not an entity.
type EventRoute = { resource: string; list: string; useUserId?: boolean }
const EVENT_ROUTES: Record<string, EventRoute> = {
  // Money — admin approves / acknowledges
  donation_submit:          { resource: 'donations',                    list: '/donations' },
  sponsorship_submit:       { resource: 'sponsorships',                 list: '/sponsorships' },
  sponsorship_cancel:       { resource: 'sponsorships',                 list: '/sponsorships' },
  in_kind_donation_submit:  { resource: 'in_kind_donations',            list: '/in-kind' },
  marketplace_order_submit: { resource: 'orders',                       list: '/marketplace' },
  // Review — admin reads and decides
  beneficiary_case_submit:  { resource: 'beneficiary_cases',            list: '/beneficiary' },
  project_request_submit:   { resource: 'beneficiary_project_requests', list: '/beneficiary' },
  support_ticket_submit:    { resource: 'support_tickets',              list: '/support' },
  // People — admin reviews submissions
  volunteer_application_submit: { resource: 'volunteer_applications',   list: '/volunteers' },
  volunteer_mission_join:       { resource: 'volunteer_applications',   list: '/volunteers' },
  marriage_profile_submit:      { resource: 'marriage',                 list: '/marriage' },
  // Identity events — the user themselves is the target
  profile_update: { resource: 'users', list: '/users', useUserId: true },
  login:          { resource: 'users', list: '/users', useUserId: true },
  register:       { resource: 'users', list: '/users', useUserId: true },
  role_select:    { resource: 'users', list: '/users', useUserId: true },
  // Non-record event — just take admin to the notifications page
  notification_mark_read: { resource: '', list: '/notifications' },
}

// Coerce Firestore numeric/string id fields to a string suitable for a URL.
function toId(v: unknown): string {
  if (v == null) return ''
  const s = String(v).trim()
  return s && s !== '0' ? s : ''
}

// Pick the best route + a human-readable "go to" label for the row's
// click affordance. Returns null when the event type has no admin action.
//
// Phase 16 behavior change — instead of dropping the admin on the single-
// record detail page, we navigate to the LIST page with `?highlight=<id>`
// in the URL. The list page reads that param via useHighlightedRow() and
// renders a pulse ring + banner on the matching row, so the admin can act
// (approve / reject) without leaving the table.
function routeForEvent(r: EventRow): { href: string; label: string } | null {
  const m = EVENT_ROUTES[r.event_type]
  if (!m) return null

  // Identity events — these are "what user did X" so they still land on the
  // detail page (no list-row to pulse — there's nothing to approve).
  if (m.useUserId) {
    const uid = toId(r.user_id)
    return uid
      ? { href: `/detail/users/${uid}`, label: 'Open user' }
      : { href: m.list, label: 'Open users' }
  }

  // Standard records — prefer entity_id, fall back to target_id.
  const id = toId(r.entity_id) || toId(r.target_id)
  if (id && m.list) {
    return { href: `${m.list}?highlight=${encodeURIComponent(id)}`, label: 'Open & review' }
  }
  return { href: m.list, label: 'Open page' }
}

const RANGE_TODAY = 'today'
const RANGE_7D = '7d'
const RANGE_ALL = 'all'

const TOPICS = ['all', 'Core', 'People', 'Money', 'Orders', 'Review'] as const
type Topic = (typeof TOPICS)[number]

function timestampMs(row: EventRow): number {
  if (typeof row.created_at_ms === 'number') return row.created_at_ms
  const ca = row.created_at as { toMillis?: () => number } | undefined
  if (ca && typeof ca.toMillis === 'function') return ca.toMillis()
  return 0
}

function formatWhen(row: EventRow): string {
  const ms = timestampMs(row)
  if (ms <= 0) return 'just now'
  return new Date(ms).toLocaleString()
}

export default function EventsFeed() {
  const navigate = useNavigate()
  const { t } = useI18n()
  // Phase 17 — the Firestore subscription + sound logic now live in
  // GlobalAlertsProvider so they keep working on every page. This component
  // is a pure rendering surface that consumes events + connection status
  // from the provider.
  const { events: rawEvents, status, error, sound, setSound, playTest } = useGlobalAlerts()
  const rows = rawEvents as unknown as EventRow[]

  const [range, setRange] = useState<typeof RANGE_TODAY | typeof RANGE_7D | typeof RANGE_ALL>(RANGE_TODAY)
  const [topic, setTopic] = useState<Topic>('all')
  const [search, setSearch] = useState('')
  const [hideRead, setHideRead] = useState(true)

  // Phase 18d — campaign-id → title map used to enrich money-event bodies.
  // Fetched ONCE on mount; the admin SPA already polls pending-counts every
  // 5s, so adding another /api/admin/campaigns call per event would be
  // wasteful. Stale-cache risk is minimal: campaigns are admin-curated and
  // change rarely, and even a 1-day-old map still produces correct titles
  // for any campaign that exists today.
  const [campaignMap, setCampaignMap] = useState<Record<number, string>>({})
  useEffect(() => {
    let cancelled = false
    type CampaignRow = { id: number; title: string }
    type Resp = { items?: CampaignRow[] }
    api
      .get<Resp>('/api/admin/campaigns', { params: { per_page: 200 } })
      .then((res) => {
        if (cancelled) return
        const map: Record<number, string> = {}
        for (const r of res.data.items ?? []) {
          if (r.id && r.title) map[r.id] = r.title
        }
        setCampaignMap(map)
      })
      .catch(() => { /* swallow — body falls back to generic copy */ })
    return () => { cancelled = true }
  }, [])

  const visible = useMemo(() => {
    const now = Date.now()
    const cutoff =
      range === RANGE_TODAY ? now - 24 * 3600 * 1000 :
      range === RANGE_7D ? now - 7 * 24 * 3600 * 1000 :
      0
    const term = search.trim().toLowerCase()
    return rows.filter((r) => {
      if (cutoff > 0 && timestampMs(r) < cutoff) return false
      if (topic !== 'all') {
        const m = metaFor(r.event_type)
        if (m.category !== topic) return false
      }
      if (hideRead && r.event_type === 'notification_mark_read') return false
      if (term) {
        const blob = (
          `${r.event_type ?? ''} ${r.name ?? ''} ${r.number ?? ''} ` +
          `${r.module ?? ''} ${r.action ?? ''} ${r.note ?? ''} ${r.event_label ?? ''}`
        ).toLowerCase()
        if (!blob.includes(term)) return false
      }
      return true
    })
  }, [rows, range, topic, search, hideRead])

  return (
    <div className="card events-feed">
      <div className="events-head">
        <div>
          <h2>{t('feed.title')}</h2>
          <div className="events-status">
            <span className={`status-dot status-${status}`} />
            <span className="muted">
              {status === 'connecting' && t('feed.connecting')}
              {status === 'connected' && t('feed.connected', { visible: visible.length, total: rows.length })}
              {status === 'error' && `${t('feed.conn_error')}${error ? ': ' + error : ''}`}
            </span>
          </div>
        </div>
        <div className="row" style={{ gap: 6 }}>
          {/* These mirror the topbar sound menu — kept here for at-glance
              control while on the dashboard. State is shared via the
              GlobalAlertsProvider so toggling here also flips the topbar
              icon and vice-versa. */}
          <button className={sound ? '' : 'secondary'} onClick={() => setSound(!sound)} title={t('feed.sound_title')}>
            {sound ? t('feed.sound_on') : t('feed.sound_off')}
          </button>
          <button className="secondary" onClick={playTest} title={t('feed.test_title')}>
            {t('feed.test')}
          </button>
        </div>
      </div>

      <div className="events-filters">
        <div className="tab-row">
          {[RANGE_TODAY, RANGE_7D, RANGE_ALL].map((r) => (
            <button
              key={r}
              className={range === r ? '' : 'secondary'}
              onClick={() => setRange(r as typeof range)}
            >
              {r === RANGE_TODAY ? t('feed.range_today') : r === RANGE_7D ? t('feed.range_7d') : t('feed.range_all')}
            </button>
          ))}
        </div>
        <div className="tab-row" style={{ flexWrap: 'wrap' }}>
          {TOPICS.map((tp) => (
            <button
              key={tp}
              className={topic === tp ? '' : 'secondary'}
              onClick={() => setTopic(tp)}
            >
              {tp}
            </button>
          ))}
        </div>
        <input
          type="search"
          placeholder={t('feed.search_placeholder')}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ flex: '1 1 200px' }}
        />
        <label className="row" style={{ gap: 6, alignItems: 'center', whiteSpace: 'nowrap' }}>
          <input type="checkbox" checked={hideRead} onChange={(e) => setHideRead(e.target.checked)} />
          <span className="muted">{t('feed.hide_read')}</span>
        </label>
      </div>

      {/* Toast is now rendered globally by GlobalAlertsProvider — it appears
          regardless of which page the admin is on. The dashboard-local
          banner was redundant and would double up. */}

      <div className="events-list">
        {status === 'error' && (
          <div className="cell-muted">{t('feed.error_help')}</div>
        )}
        {status !== 'error' && visible.length === 0 && (
          <div className="cell-muted">{t('feed.no_events')}</div>
        )}
        {visible.map((r) => {
          const m = metaFor(r.event_type)
          // Resolve a click target from the event type + ids. May be null for
          // event types we don't (yet) know how to route — those rows stay
          // non-interactive instead of dead-ending in a 404.
          const route = routeForEvent(r)
          const handleClick = route ? () => navigate(route.href) : undefined
          const handleKeyDown = route
            ? (e: React.KeyboardEvent<HTMLDivElement>) => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault()
                  navigate(route.href)
                }
              }
            : undefined
          return (
            <div
              className={`event-row${route ? ' is-clickable' : ''}`}
              key={r.id}
              role={route ? 'button' : undefined}
              tabIndex={route ? 0 : undefined}
              onClick={handleClick}
              onKeyDown={handleKeyDown}
              title={route ? route.label : undefined}
              aria-label={route ? `${t('common.' + (BADGE_KEY[m.badge] ?? 'bdg_event'))}: ${bodyFor(r, campaignMap, t)} — ${route.label}` : undefined}
            >
              <span className={`event-icon tone-${m.tone}`}>{m.icon}</span>
              <div className="cell-stack" style={{ flex: 1, minWidth: 0 }}>
                <div className="row" style={{ gap: 6, alignItems: 'baseline' }}>
                  <strong>{r.event_type || 'event'}</strong>
                  <span className={`badge tone-${m.tone}`}>{t('common.' + (BADGE_KEY[m.badge] ?? 'bdg_event'))}</span>
                  <span className="badge">{t('common.' + (CAT_KEY[m.category] ?? 'cat_activity'))}</span>
                </div>
                <span className="muted">{actorFor(r)} · {bodyFor(r, campaignMap, t)}</span>
              </div>
              <span className="muted" style={{ whiteSpace: 'nowrap' }}>{formatWhen(r)}</span>
              {route && <span className="event-chevron" aria-hidden="true">›</span>}
            </div>
          )
        })}
      </div>
    </div>
  )
}
