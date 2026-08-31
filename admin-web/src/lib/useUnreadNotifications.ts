// useUnreadNotifications.ts — Task 3 (owner ask: "show the notification
// badge and color code and filter").
//
// Why not the shared pendingCounts provider (lib/pendingCounts.tsx)? That
// context is a thin mirror of one fixed backend struct
// (`handlers.PendingCounts`), fetched from one endpoint. Adding a
// notifications field to it means a backend change, and this pass is scoped
// to admin-web only (a sibling agent owns the Flutter/backend side of this
// branch). /api/admin/notifications already accepts a `read_status` filter
// (NotificationsPage.tsx uses it today) and returns `total_items` in the
// same page envelope every other admin list uses — asking it for
// read_status=unread, per_page=1 gets the unread count for free with zero
// backend changes, at the cost of one extra small request.
//
// Same 5s / visibility-paused cadence as the rest of the dashboard's live
// polling (useLivePoll — mirrors NotificationsPage's own poll).

import { useEffect, useState } from 'react'
import { api } from './api'
import { useAuth } from './auth'
import { useLivePoll } from './useLivePoll'
import type { AdminPageResp, AdminNotification } from './api-types'

const POLL_MS = 5_000

/**
 * Returns the current count of unread admin notifications, polled live.
 * Returns 0 while signed out, disabled, or before the first successful
 * fetch — never throws, so a transient failure just leaves the last known
 * count on screen (identical failure handling to pendingCounts.tsx).
 *
 * `enabled` (default true) exists because this hook is called once per
 * rendered sidebar item (AppShell's NavItemLink is mounted per nav row) —
 * only the "Notifications" row passes true, so this poll runs exactly
 * once for the whole sidebar rather than once per item.
 */
export function useUnreadNotificationsCount(enabled = true): number {
  const { user } = useAuth()
  const [count, setCount] = useState(0)
  const active = enabled && !!user

  const fetchOnce = async () => {
    if (!active) return
    try {
      const res = await api.get<AdminPageResp<AdminNotification>>('/api/admin/notifications', {
        params: { page: 1, per_page: 1, read_status: 'unread' },
      })
      setCount(res.data.total_items ?? 0)
    } catch {
      // Swallow — next tick retries, same as pendingCounts.tsx's poll.
    }
  }

  useEffect(() => {
    if (!active) { setCount(0); return }
    fetchOnce()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active])

  useLivePoll(fetchOnce, POLL_MS, { enabled: active })

  return count
}
