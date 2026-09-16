// globalAlertsContext.ts — the alert stream's shared types, context and hook.
//
// Split out of globalAlerts.tsx because a file that exports a component may
// not also export a hook, and a context must not live beside one either: fast
// refresh recreates a module's bindings on every edit, so the context would be
// swapped for a brand-new one and the Provider/consumer pair would come apart
// mid-session (react-refresh/only-export-components).

import { createContext, useContext } from 'react'

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

// === Context shape ===
export type Ctx = {
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

export const GlobalAlertsContext = createContext<Ctx | null>(null)

// useGlobalAlerts — sound controls + access to the shared events stream.
export function useGlobalAlerts(): Ctx {
  const ctx = useContext(GlobalAlertsContext)
  if (!ctx) throw new Error('useGlobalAlerts must be inside <GlobalAlertsProvider>')
  return ctx
}
