// globalAlerts.tsx — app-wide chime, floating toast, and (opt-in) OS
// notification when the tab is hidden.
//
// Source: polls the Go backend GET /api/admin/events (Postgres `app_events`)
// every 5s — migrated from the old Firestore `events` onSnapshot subscription.
//
// Architecture:
//
//   <GlobalAlertsProvider>
//     ├── owns one polling loop (lives as long as the user is signed in)
//     ├── plays a per-event-type chime for genuinely-new rows
//     ├── shows an in-app <AlertToast> (top-right, click to jump)
//     ├── shows a window.Notification when the document is hidden + the
//     │   admin has granted permission
//     └── exposes { sound, setSound, requestOSNotifications, … } via
//         useGlobalAlerts() so the topbar speaker menu can render +
//         control state.
//
// Why a provider and not a hook in EventsFeed?
//   • EventsFeed only mounts on /. If the admin is on any other page, the
//     old listener was dead — they missed every alert.
//   • Multiple consumers of the same Firestore subscription is wasteful
//     and creates double-fire risk. A provider centralises the source.
//
// Persistence:
//   • Sound on/off    → localStorage "alerts.sound"      (default: "on")
//   • OS notify       → localStorage "alerts.osNotify"   (default: "off")
//
// Browser autoplay rules: WebAudio is suspended until the first user
// gesture. We auto-resume on the FIRST click anywhere in the document
// (capture phase). Until that happens, the topbar button shows a soft
// amber pulse ("needs-unlock").

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from './api'
import { useAuth } from './auth'

// Mirrors the EventRow type in EventsFeed.tsx. Kept local (with the fields
// this provider actually consumes) so the two files don't have to share
// a third module.
export type AlertEvent = {
  id: string | number
  event_type: string
  created_at_ms?: number
  name?: string
  number?: string
  user_id?: number | string
  entity_id?: number | string
  target_id?: number | string
  note?: string
  event_label?: string
  module?: string
  action?: string
}

// === route + meta tables (mirrors EventsFeed; kept local to avoid coupling) ===
type RouteSpec = { list: string; useUserId?: boolean }
const ROUTE_TABLE: Record<string, RouteSpec> = {
  donation_submit:              { list: '/donations' },
  sponsorship_submit:           { list: '/sponsorships' },
  sponsorship_cancel:           { list: '/sponsorships' },
  in_kind_donation_submit:      { list: '/in-kind' },
  marketplace_order_submit:     { list: '/marketplace' },
  beneficiary_case_submit:      { list: '/beneficiary' },
  project_request_submit:       { list: '/beneficiary' },
  support_ticket_submit:        { list: '/support' },
  volunteer_application_submit: { list: '/volunteers' },
  volunteer_mission_join:       { list: '/volunteers' },
  marriage_profile_submit:      { list: '/marriage' },
  profile_update:               { list: '/users', useUserId: true },
  login:                        { list: '/users', useUserId: true },
  register:                     { list: '/users', useUserId: true },
  role_select:                  { list: '/users', useUserId: true },
}

const BADGE_LABEL: Record<string, string> = {
  donation_submit:              'New donation',
  sponsorship_submit:           'New sponsorship',
  sponsorship_cancel:           'Sponsorship cancelled',
  in_kind_donation_submit:      'New in-kind donation',
  marketplace_order_submit:     'New marketplace order',
  beneficiary_case_submit:      'New beneficiary case',
  project_request_submit:       'New project request',
  support_ticket_submit:        'New support ticket',
  volunteer_application_submit: 'New volunteer application',
  volunteer_mission_join:       'Volunteer joined mission',
  marriage_profile_submit:      'New marriage profile',
}

function toId(v: unknown): string {
  if (v == null) return ''
  const s = String(v).trim()
  return s && s !== '0' ? s : ''
}

// Compute the route a click on this alert should navigate to. Reuses the
// `?highlight=<id>` convention used by EventsFeed so the destination page's
// useHighlightedRow() picks up the row + pulses it.
function routeForAlert(e: AlertEvent): string | null {
  const m = ROUTE_TABLE[e.event_type]
  if (!m) return null
  if (m.useUserId) {
    const uid = toId(e.user_id)
    return uid ? `/detail/users/${uid}` : m.list
  }
  const id = toId(e.entity_id) || toId(e.target_id)
  return id ? `${m.list}?highlight=${encodeURIComponent(id)}` : m.list
}

// Per-event-type chime presets — same numbers as EventsFeed.tsx originally.
// Falls back to a neutral middle pitch for unknown types.
function playChime(audioCtx: AudioContext, eventType: string) {
  const presets: Record<string, { freq: number; dur: number }> = {
    donation_submit:          { freq: 880, dur: 0.18 },
    sponsorship_submit:       { freq: 740, dur: 0.18 },
    marketplace_order_submit: { freq: 660, dur: 0.16 },
    in_kind_donation_submit:  { freq: 700, dur: 0.16 },
    beneficiary_case_submit:  { freq: 520, dur: 0.22 },
    project_request_submit:   { freq: 500, dur: 0.22 },
    support_ticket_submit:    { freq: 440, dur: 0.24 },
    register:                 { freq: 620, dur: 0.14 },
    login:                    { freq: 600, dur: 0.10 },
  }
  const p = presets[eventType] ?? { freq: 540, dur: 0.12 }
  const osc = audioCtx.createOscillator()
  const gain = audioCtx.createGain()
  osc.type = 'sine'
  osc.frequency.value = p.freq
  gain.gain.value = 0
  gain.gain.linearRampToValueAtTime(0.18, audioCtx.currentTime + 0.01)
  gain.gain.linearRampToValueAtTime(0, audioCtx.currentTime + p.dur)
  osc.connect(gain).connect(audioCtx.destination)
  osc.start()
  osc.stop(audioCtx.currentTime + p.dur + 0.02)
}

// === Context shape ===
type Ctx = {
  /** Latest 100 events (sorted desc by created_at_ms). The dashboard feed
   *  reuses this so it doesn't open a second subscription. */
  events: AlertEvent[]
  /** Subscription state — surfaces connection status to the dashboard. */
  status: 'connecting' | 'connected' | 'error'
  /** Last connection error, if status === 'error'. */
  error: string | null
  /** Sound toggle. setSound persists to localStorage. */
  sound: boolean
  setSound: (on: boolean) => void
  /** Whether the audio context has been "unlocked" by a user gesture.
   *  When sound=true but unlocked=false, the topbar button pulses. */
  audioUnlocked: boolean
  /** OS-notification toggle (only meaningful once permission is granted). */
  osNotify: boolean
  setOsNotify: (on: boolean) => void
  /** Current Notification permission. */
  notifPermission: NotificationPermission | 'unsupported'
  /** Asks the browser for Notification permission (one-time prompt). */
  requestOSNotifications: () => Promise<void>
  /** Fires the chime once for the admin to confirm sound works. */
  playTest: () => void
}

const GlobalAlertsContext = createContext<Ctx | null>(null)

// LocalStorage helpers — small wrappers that don't throw on private-mode
// or sandboxed iframes.
function readBoolLS(key: string, fallback: boolean): boolean {
  try {
    const v = localStorage.getItem(key)
    if (v == null) return fallback
    return v === '1' || v === 'true' || v === 'on'
  } catch {
    return fallback
  }
}
function writeBoolLS(key: string, v: boolean) {
  try { localStorage.setItem(key, v ? '1' : '0') } catch {}
}

export function GlobalAlertsProvider({ children }: { children: ReactNode }) {
  const navigate = useNavigate()
  const { user } = useAuth()

  // Persisted user preferences.
  const [sound, setSoundState] = useState<boolean>(() => readBoolLS('alerts.sound', true))
  const [osNotify, setOsNotifyState] = useState<boolean>(() => readBoolLS('alerts.osNotify', false))

  // Audio context + unlock state.
  const audioCtxRef = useRef<AudioContext | null>(null)
  const [audioUnlocked, setAudioUnlocked] = useState<boolean>(false)

  // Firestore subscription state.
  const [events, setEvents] = useState<AlertEvent[]>([])
  const [status, setStatus] = useState<'connecting' | 'connected' | 'error'>('connecting')
  const [error, setError] = useState<string | null>(null)

  // Seen-id set lets us detect genuinely-new events vs. backfilled ones on
  // initial snapshot. We don't fire sounds for backfill.
  const seenIdsRef = useRef<Set<string>>(new Set())
  const firstSnapshotRef = useRef<boolean>(true)

  // In-app toast — single-slot (most recent event). Auto-clears after 6s.
  const [toast, setToast] = useState<AlertEvent | null>(null)

  // Browser Notification permission (cached + responsive to requests).
  const [notifPermission, setNotifPermission] = useState<NotificationPermission | 'unsupported'>(
    () => (typeof Notification === 'undefined' ? 'unsupported' : Notification.permission),
  )

  // ===== persisted-state setters =====
  const setSound = useCallback((on: boolean) => {
    setSoundState(on)
    writeBoolLS('alerts.sound', on)
    if (on) ensureAudio()
  }, [])
  const setOsNotify = useCallback((on: boolean) => {
    setOsNotifyState(on)
    writeBoolLS('alerts.osNotify', on)
  }, [])

  // ===== WebAudio plumbing =====
  function ensureAudio(): AudioContext | null {
    if (audioCtxRef.current) return audioCtxRef.current
    type Win = Window & { webkitAudioContext?: typeof AudioContext }
    const Ctor = window.AudioContext ?? (window as Win).webkitAudioContext
    if (!Ctor) return null
    const ctx = new Ctor()
    audioCtxRef.current = ctx
    return ctx
  }

  // First user click ANYWHERE unlocks the audio context (browser policy).
  // We listen in capture phase so we run before any stopPropagation by
  // other handlers. Removes itself after one fire.
  useEffect(() => {
    function unlock() {
      const ctx = ensureAudio()
      if (ctx && ctx.state === 'suspended') void ctx.resume()
      setAudioUnlocked(true)
      window.removeEventListener('pointerdown', unlock, true)
      window.removeEventListener('keydown', unlock, true)
    }
    window.addEventListener('pointerdown', unlock, true)
    window.addEventListener('keydown', unlock, true)
    return () => {
      window.removeEventListener('pointerdown', unlock, true)
      window.removeEventListener('keydown', unlock, true)
    }
  }, [])

  // ===== Backend polling (Postgres `app_events` via /api/admin/events) =====
  // Replaces the old Firestore onSnapshot subscription. We poll the most recent
  // 100 events every 5s and diff against the seen-id set to detect genuinely-new
  // rows (so we don't chime on the initial backfill).
  useEffect(() => {
    // Don't poll when signed out — saves bandwidth + avoids 401s.
    if (!user) {
      setEvents([])
      setStatus('connecting')
      return
    }

    let cancelled = false

    function handleSnapshot(next: AlertEvent[]) {
      // Detect new rows once we've seen the initial backfill.
      if (!firstSnapshotRef.current) {
        const newRows = next.filter((r) => !seenIdsRef.current.has(String(r.id)))
        if (newRows.length > 0) {
          const first = newRows[0]

          // 1) Chime — only if user enabled it AND audio is unlocked.
          if (sound) {
            const ctx = ensureAudio()
            if (ctx) {
              if (ctx.state === 'suspended') void ctx.resume()
              if (audioUnlocked) playChime(ctx, first.event_type)
            }
          }

          // 2) In-app toast (always show — the visual cue is silent).
          setToast(first)

          // 3) OS notification when tab is hidden + admin opted in.
          if (
            osNotify
            && notifPermission === 'granted'
            && typeof document !== 'undefined'
            && document.hidden
          ) {
            try {
              const body =
                first.note?.trim() ||
                first.event_label?.trim() ||
                [first.module, first.action].filter(Boolean).join(' · ') ||
                ''
              new Notification(
                BADGE_LABEL[first.event_type] ?? first.event_type,
                {
                  body: [first.name, body].filter(Boolean).join(' — '),
                  tag: `alerts-${first.event_type}`,  // collapses duplicates
                  icon: '/favicon.ico',
                },
              )
            } catch {
              // Some browsers throw on rapid-fire Notification constructions.
              // Silently swallow; we still have the toast + sidebar badge.
            }
          }
        }
      }

      seenIdsRef.current = new Set(next.map((r) => String(r.id)))
      firstSnapshotRef.current = false
      setEvents(next)
      setStatus('connected')
    }

    async function poll() {
      try {
        const res = await api.get<{ items?: AlertEvent[] }>('/api/admin/events', {
          params: { limit: 100 },
        })
        if (cancelled) return
        handleSnapshot(res.data.items ?? [])
      } catch (err) {
        if (cancelled) return
        // eslint-disable-next-line no-console
        console.error('global alerts feed error:', err)
        setStatus('error')
        setError((err as Error)?.message || String(err))
      }
    }

    poll()
    const timer = window.setInterval(poll, 5000)
    return () => {
      cancelled = true
      window.clearInterval(timer)
    }
    // sound/osNotify/audioUnlocked are read inside the poll closure; we keep the
    // deps minimal so the interval isn't torn down + recreated on every toggle.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user])

  // Auto-dismiss toast after 6 seconds.
  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => setToast(null), 6000)
    return () => clearTimeout(t)
  }, [toast])

  const requestOSNotifications = useCallback(async () => {
    if (typeof Notification === 'undefined') return
    try {
      const perm = await Notification.requestPermission()
      setNotifPermission(perm)
      if (perm === 'granted') setOsNotify(true)
    } catch {
      // ignore — permission stays whatever it was
    }
  }, [setOsNotify])

  const playTest = useCallback(() => {
    const ctx = ensureAudio()
    if (!ctx) return
    if (ctx.state === 'suspended') void ctx.resume()
    setAudioUnlocked(true)
    playChime(ctx, 'donation_submit')
  }, [])

  const value = useMemo<Ctx>(
    () => ({
      events,
      status,
      error,
      sound,
      setSound,
      audioUnlocked,
      osNotify,
      setOsNotify,
      notifPermission,
      requestOSNotifications,
      playTest,
    }),
    [events, status, error, sound, setSound, audioUnlocked, osNotify, setOsNotify, notifPermission, requestOSNotifications, playTest],
  )

  return (
    <GlobalAlertsContext.Provider value={value}>
      {children}
      {/* Floating toast — fixed top-right, clicking jumps to the row. */}
      {toast && (
        <div
          className="alert-toast"
          role="alert"
          onClick={() => {
            const href = routeForAlert(toast)
            if (href) navigate(href)
            setToast(null)
          }}
        >
          <span className="at-icon" aria-hidden="true">●</span>
          <div className="at-body">
            <strong>{BADGE_LABEL[toast.event_type] ?? toast.event_type}</strong>
            <div className="muted">
              {toast.name ?? 'App user'}
              {toast.note ? ` — ${toast.note}` : ''}
            </div>
          </div>
          <button
            type="button"
            className="at-close"
            aria-label="Dismiss"
            onClick={(e) => { e.stopPropagation(); setToast(null) }}
          >×</button>
        </div>
      )}
    </GlobalAlertsContext.Provider>
  )
}

// useGlobalAlerts — sound controls + access to the shared events stream.
export function useGlobalAlerts(): Ctx {
  const ctx = useContext(GlobalAlertsContext)
  if (!ctx) throw new Error('useGlobalAlerts must be inside <GlobalAlertsProvider>')
  return ctx
}
