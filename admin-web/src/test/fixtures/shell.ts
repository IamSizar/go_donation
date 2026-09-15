/**
 * shell.ts — what the dashboard shell requests on every screen, plus the users
 * search behind the member picker.
 *
 * As soon as a staff member is signed in, whatever page is open, App.tsx's
 * providers and AppShell request:
 *   GET /api/admin/pending-counts            lib/pendingCounts.tsx, every 5 s
 *   GET /api/admin/events?limit=100          lib/globalAlerts.tsx, every 5 s
 *   GET /api/admin/notifications?…unread     lib/useUnreadNotifications.ts
 * and the member picker searches
 *   GET /api/admin/users?q=&per_page=        components/UserPicker.tsx
 *
 * Each export names the Go handler whose JSON it mirrors. Every name, number
 * and message here is invented. Plain data with type-only imports, so Node can
 * load this file with --experimental-strip-types.
 */
import type { AdminNotification } from '../../lib/api-types'
import type { PendingCounts } from '../../lib/pendingCounts'

// ─── Pending counts ───

/**
 * GET /api/admin/pending-counts — a flat object, not an envelope
 * (handlers/pending_counts.go, PendingCounts). `total` is the server's sum.
 */
export const PENDING_COUNTS: PendingCounts = {
  donations: 3,
  sponsorships: 1,
  beneficiary: 2,
  marketplace: 0,
  support: 1,
  in_kind: 0,
  volunteers: 2,
  mission_signups: 1,
  marriage: 1,
  registrations: 4,
  total: 15,
}

// ─── Live events feed ───

/** One row of GET /api/admin/events (internal/events/store.go, Event). */
export type AdminEvent = {
  id: number
  event_type: string
  event_label?: string
  module?: string
  action?: string
  status?: string
  source?: string
  user_id?: number
  name?: string
  number?: string
  entity_id?: number
  amount?: number
  currency?: string
  note?: string
  is_read: boolean
  created_at_ms: number
}

/** GET /api/admin/events items, newest first (handlers/events.go, AdminList). */
export const ADMIN_EVENTS: AdminEvent[] = [
  {
    id: 9003,
    event_type: 'donation_submit',
    event_label: 'Donation submitted',
    module: 'donations',
    action: 'submit',
    source: 'app',
    user_id: 104,
    name: 'Omar Khalid',
    number: '+9647701114521',
    entity_id: 7781,
    amount: 50000,
    currency: 'IQD',
    is_read: false,
    created_at_ms: Date.UTC(2026, 8, 15, 8, 40),
  },
  {
    id: 9002,
    event_type: 'sponsorship_submit',
    event_label: 'Sponsorship submitted',
    module: 'sponsorships',
    action: 'submit',
    source: 'app',
    user_id: 102,
    name: 'Layla Hassan',
    number: '+9647702223344',
    entity_id: 412,
    is_read: false,
    created_at_ms: Date.UTC(2026, 8, 15, 8, 12),
  },
  {
    id: 9001,
    event_type: 'guest_login',
    event_label: 'Guest login',
    module: 'auth',
    action: 'login',
    source: 'app',
    is_read: true,
    created_at_ms: Date.UTC(2026, 8, 15, 7, 55),
  },
]

// ─── Staff notifications ───

/**
 * GET /api/admin/notifications rows (handlers/admin_lists.go,
 * adminNotification). The route pages and filters them by read_status.
 */
export const ADMIN_NOTIFICATIONS: AdminNotification[] = [
  {
    id: 5003,
    user_id: null,
    role_id: null,
    title: 'New connect request',
    title_ar: 'طلب تواصل جديد',
    body: 'A donor asked to be put in touch about case HC-2291.',
    body_ar: 'طلب متبرع التواصل بخصوص الحالة HC-2291.',
    notification_type: 'chat_group_connect_request',
    notification_category: 'messages',
    priority: 2,
    is_read: 0,
    created_at: '2026-09-15T08:30:00Z',
    read_at: null,
  },
  {
    id: 5002,
    user_id: null,
    role_id: null,
    title: 'Donation awaiting confirmation',
    title_ar: 'تبرع بانتظار التأكيد',
    body: 'Omar Khalid registered a donation of 50,000 IQD.',
    body_ar: 'سجّل عمر خالد تبرعاً بقيمة 50,000 دينار.',
    notification_type: 'donation_submit',
    notification_category: 'donations',
    priority: 1,
    is_read: 0,
    created_at: '2026-09-15T08:40:00Z',
    read_at: null,
  },
  {
    id: 5001,
    user_id: null,
    role_id: null,
    title: 'Weekly report ready',
    title_ar: 'التقرير الأسبوعي جاهز',
    body: 'The report for 8–14 September is available.',
    body_ar: 'تقرير الفترة 8–14 أيلول متاح.',
    notification_type: 'report_ready',
    notification_category: 'reports',
    priority: 0,
    is_read: 1,
    created_at: '2026-09-14T18:00:00Z',
    read_at: '2026-09-14T19:02:00Z',
  },
]

// ─── Users search ───

/**
 * One row of GET /api/admin/users `data` (internal/users/users.go, the
 * paginated list item). UserPicker reads user_id, phone, role_id and
 * profile.full_name; the other fields are there so a page showing more of the
 * row still renders.
 */
export type AdminUserRow = {
  user_id: number
  phone: string
  role_id: number
  created_at: string
  registration_status: string
  staff_tier: string
  profile: { profile_id: number; full_name: string | null; profile_picture: string | null } | null
}

/**
 * The app users the member picker can find. role_id follows UserPicker's
 * ROLE_LABEL_KEY: 1 donor, 2 beneficiary, 3 volunteer. Two share the name
 * Layla so a search visibly narrows the list without emptying it.
 */
export const ADMIN_USERS: AdminUserRow[] = [
  user(101, '+9647701002001', 1, 'Layla Hassan'),
  user(102, '+9647702223344', 1, 'Layla Mahmoud'),
  user(103, '+9647503334455', 2, 'Sara Ali'),
  user(104, '+9647701114521', 1, 'Omar Khalid'),
  user(105, '+9647814445566', 3, 'Yusuf Kareem'),
  user(106, '+9647705556677', 3, 'Noor Jabbar'),
]

/** Builds one approved app-user row with a profile. */
function user(id: number, phone: string, roleId: number, fullName: string): AdminUserRow {
  return {
    user_id: id,
    phone,
    role_id: roleId,
    created_at: '2026-06-01T10:00:00Z',
    registration_status: 'approved',
    staff_tier: 'user',
    profile: { profile_id: id + 1000, full_name: fullName, profile_picture: null },
  }
}
