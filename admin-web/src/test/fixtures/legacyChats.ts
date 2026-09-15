/**
 * legacyChats.ts — the three chat systems that predate chat groups, as their
 * admin pages load them.
 *
 *   Donor ↔ owner, and support  GET /api/admin/chats?kind=direct|support     pages/MessagesPage.tsx
 *                               GET /api/admin/chats/:id/messages
 *                               GET /api/admin/chats/:id/contact-blocks      components/ContactBlocksPanel.tsx
 *   Marriage (staff-mediated)   GET /api/admin/marriage/chats                pages/MarriageChatsPage.tsx
 *                               GET /api/admin/marriage/chats/:id/messages
 *   Staff ↔ staff               GET /api/admin/staff-chats                   pages/StaffChatPage.tsx
 *                               GET /api/admin/staff-chats/:id/messages
 *                               GET /api/admin/staff-directory
 *
 * The row types copy the local types those pages declare, which mirror the Go
 * structs (internal/chat, internal/marriagechat, internal/staffchat). Each
 * conversation shows a different state: active, paused with a reason, pending
 * with no messages, and an archived, ended staff chat. Every person, message
 * and number is invented. Type-only import, so Node can load this file with
 * --experimental-strip-types.
 */
import type { ContactBlock } from '../../components/ContactBlocksPanel'

// ─── Types ───

/** The staff-controlled lifecycle every thread row carries (migration 117). */
type LifecycleFields = {
  lifecycle: 'open' | 'paused' | 'ended'
  lifecycle_reason: string | null
  is_archived: boolean
}

/** A donor ↔ owner or support thread row (MessagesPage.tsx, AdminThread). */
export type DonorThread = LifecycleFields & {
  id: number
  status: 'pending' | 'active' | 'declined'
  campaign_id: number | null
  campaign_title: string | null
  donor_user_id: number
  donor_name: string | null
  donor_phone: string | null
  owner_user_id: number
  owner_name: string | null
  owner_phone: string | null
  assigned_staff_user_id: number | null
  assigned_staff_name: string | null
  message_count: number
  last_message: string | null
  last_message_at: string | null
  created_at: string
  updated_at: string
}

/**
 * A donor-chat message (MessagesPage.tsx, ChatMessage). sender_role is the
 * sender's app role_id when a participant sent it (1 donor, 2 beneficiary),
 * and 0 when staff replied as support (chat.RoleSupport).
 */
export type DonorMessage = {
  id: number
  thread_id: number
  sender_user_id: number
  sender_role: number
  sender_name: string | null
  body: string
  created_at: string
}

/** A marriage chat thread row (MarriageChatsPage.tsx, AdminThread). */
export type MarriageThread = LifecycleFields & {
  id: number
  status: 'pending' | 'active' | 'declined'
  profile_id: number
  profile_code: string
  requester_user_id: number
  requester_name: string | null
  requester_phone: string | null
  owner_user_id: number
  owner_name: string | null
  owner_phone: string | null
  message_count: number
  last_message: string | null
  last_message_at: string | null
  created_at: string
  updated_at: string
}

/** A marriage chat message (MarriageChatsPage.tsx, ChatMessage). */
export type MarriageMessage = {
  id: number
  thread_id: number
  sender_user_id: number
  sender_role: 'requester' | 'owner' | 'staff'
  sender_name: string | null
  body: string
  created_at: string
}

/** A staff chat thread row, from the signed-in staff member's side (staffchat.ThreadView). */
export type StaffThread = LifecycleFields & {
  id: number
  other_user_id: number
  other_name: string | null
  other_staff_tier: string | null
  last_message: string | null
  last_message_at: string | null
  unread_count: number
  updated_at: string
}

/** A staff chat message (staffchat.Message). */
export type StaffMessage = {
  id: number
  thread_id: number
  sender_user_id: number
  sender_name: string | null
  body: string
  created_at: string
}

/** One other dashboard account a staff chat can be started with (staffchat.DirectoryEntry). */
export type StaffDirectoryEntry = {
  user_id: number
  full_name: string | null
  phone: string
  staff_tier: string
}

const OPEN: LifecycleFields = { lifecycle: 'open', lifecycle_reason: null, is_archived: false }

// ─── Donor ↔ owner, and support ───

/** GET /api/admin/chats?kind=direct items. */
export const DONOR_THREADS: DonorThread[] = [
  {
    ...OPEN,
    id: 7,
    status: 'active',
    campaign_id: 12,
    campaign_title: 'Back to school',
    donor_user_id: 101,
    donor_name: 'Layla Hassan',
    donor_phone: '+9647701002001',
    owner_user_id: 103,
    owner_name: 'Sara Ali',
    owner_phone: '+9647503334455',
    assigned_staff_user_id: null,
    assigned_staff_name: null,
    message_count: 3,
    last_message: 'See you at the distribution point on Thursday.',
    last_message_at: '2026-09-14T15:20:00Z',
    created_at: '2026-09-12T11:00:00Z',
    updated_at: '2026-09-14T15:20:00Z',
  },
  {
    id: 8,
    lifecycle: 'paused',
    lifecycle_reason: 'Waiting for the case review to finish.',
    is_archived: false,
    status: 'active',
    campaign_id: 15,
    campaign_title: 'Winter blankets',
    donor_user_id: 104,
    donor_name: 'Omar Khalid',
    donor_phone: '+9647701114521',
    owner_user_id: 107,
    owner_name: 'Hadi Salman',
    owner_phone: '+9647716667788',
    assigned_staff_user_id: 1,
    assigned_staff_name: 'Rana Aziz',
    message_count: 2,
    last_message: 'We are pausing this conversation while the case is reviewed.',
    last_message_at: '2026-09-13T12:05:00Z',
    created_at: '2026-09-13T09:00:00Z',
    updated_at: '2026-09-13T12:05:00Z',
  },
  {
    ...OPEN,
    id: 9,
    status: 'pending',
    campaign_id: null,
    campaign_title: null,
    donor_user_id: 102,
    donor_name: 'Layla Mahmoud',
    donor_phone: '+9647702223344',
    owner_user_id: 103,
    owner_name: 'Sara Ali',
    owner_phone: '+9647503334455',
    assigned_staff_user_id: null,
    assigned_staff_name: null,
    message_count: 0,
    last_message: null,
    last_message_at: null,
    created_at: '2026-09-15T07:45:00Z',
    updated_at: '2026-09-15T07:45:00Z',
  },
]

/**
 * GET /api/admin/chats?kind=support items. A support thread stores the app
 * user as donor_user_id and the support account as owner_user_id, with no
 * campaign (chat.RequestSupportThread).
 */
export const SUPPORT_THREADS: DonorThread[] = [
  {
    ...OPEN,
    id: 20,
    status: 'active',
    campaign_id: null,
    campaign_title: null,
    donor_user_id: 105,
    donor_name: 'Yusuf Kareem',
    donor_phone: '+9647814445566',
    owner_user_id: 1,
    owner_name: 'Rana Aziz',
    owner_phone: '+9647700000001',
    assigned_staff_user_id: 1,
    assigned_staff_name: 'Rana Aziz',
    message_count: 2,
    last_message: 'Try signing out and in again; the new schedule will load.',
    last_message_at: '2026-09-15T06:40:00Z',
    created_at: '2026-09-15T06:30:00Z',
    updated_at: '2026-09-15T06:40:00Z',
  },
]

/** GET /api/admin/chats/:id/messages items per thread, oldest first. */
export const DONOR_MESSAGES: Record<number, DonorMessage[]> = {
  7: [
    donorMsg(7001, 7, 101, 1, 'Layla Hassan', 'I bought the notebooks. When can I drop them off?', '2026-09-14T14:50:00Z'),
    donorMsg(7002, 7, 103, 2, 'Sara Ali', 'Thank you! Thursday morning works for us.', '2026-09-14T15:05:00Z'),
    donorMsg(7003, 7, 101, 1, 'Layla Hassan', 'See you at the distribution point on Thursday.', '2026-09-14T15:20:00Z'),
  ],
  8: [
    donorMsg(7101, 8, 104, 1, 'Omar Khalid', 'Can I send the blankets directly to the family?', '2026-09-13T11:50:00Z'),
    donorMsg(7102, 8, 1, 0, 'Rana Aziz', 'We are pausing this conversation while the case is reviewed.', '2026-09-13T12:05:00Z'),
  ],
  9: [],
  20: [
    donorMsg(7201, 20, 105, 3, 'Yusuf Kareem', 'The app still shows last week\'s mission schedule.', '2026-09-15T06:30:00Z'),
    donorMsg(7202, 20, 1, 0, 'Rana Aziz', 'Try signing out and in again; the new schedule will load.', '2026-09-15T06:40:00Z'),
  ],
}

/** GET /api/admin/chats/:id/contact-blocks items per thread, newest first. */
export const DONOR_CONTACT_BLOCKS: Record<number, ContactBlock[]> = {
  7: [],
  8: [
    {
      id: 301,
      thread_id: 8,
      sender_user_id: 104,
      sender_name: 'Omar Khalid',
      kind: 'phone',
      match_count: 1,
      redacted_body: 'Call me on ••• and I will bring them over',
      created_at: '2026-09-13T11:48:00Z',
    },
  ],
  9: [],
  20: [],
}

// ─── Marriage ───

/** GET /api/admin/marriage/chats items. */
export const MARRIAGE_THREADS: MarriageThread[] = [
  {
    ...OPEN,
    id: 51,
    status: 'active',
    profile_id: 3301,
    profile_code: 'MP-3301',
    requester_user_id: 108,
    requester_name: 'Karim Adel',
    requester_phone: '+9647727778899',
    owner_user_id: 109,
    owner_name: 'Huda Salim',
    owner_phone: '+9647738889900',
    message_count: 3,
    last_message: 'The family agreed to a meeting at the centre on Saturday.',
    last_message_at: '2026-09-14T13:00:00Z',
    created_at: '2026-09-11T10:00:00Z',
    updated_at: '2026-09-14T13:00:00Z',
  },
  {
    ...OPEN,
    id: 52,
    status: 'pending',
    profile_id: 3317,
    profile_code: 'MP-3317',
    requester_user_id: 110,
    requester_name: 'Ali Mahdi',
    requester_phone: '+9647749990011',
    owner_user_id: 111,
    owner_name: 'Maryam Nasser',
    owner_phone: '+9647750001122',
    message_count: 0,
    last_message: null,
    last_message_at: null,
    created_at: '2026-09-15T08:00:00Z',
    updated_at: '2026-09-15T08:00:00Z',
  },
]

/** GET /api/admin/marriage/chats/:id/messages items per thread, oldest first. */
export const MARRIAGE_MESSAGES: Record<number, MarriageMessage[]> = {
  51: [
    marriageMsg(5101, 51, 108, 'requester', 'Karim Adel', 'I would like to arrange a family meeting.', '2026-09-12T09:00:00Z'),
    marriageMsg(5102, 51, 109, 'owner', 'Huda Salim', 'My family is open to that.', '2026-09-13T18:30:00Z'),
    marriageMsg(5103, 51, 1, 'staff', 'Rana Aziz', 'The family agreed to a meeting at the centre on Saturday.', '2026-09-14T13:00:00Z'),
  ],
  52: [],
}

// ─── Staff ↔ staff ───

/** GET /api/admin/staff-chats?include_archived=1 items, for staff member 1. */
export const STAFF_THREADS: StaffThread[] = [
  {
    ...OPEN,
    id: 61,
    other_user_id: 2,
    other_name: 'Ahmed Faris',
    other_staff_tier: 'admin',
    last_message: 'Can you review the two pending connect requests today?',
    last_message_at: '2026-09-15T08:50:00Z',
    unread_count: 1,
    updated_at: '2026-09-15T08:50:00Z',
  },
  {
    id: 62,
    lifecycle: 'ended',
    lifecycle_reason: 'Handover complete.',
    is_archived: true,
    other_user_id: 3,
    other_name: 'Zainab Kadhim',
    other_staff_tier: 'employee',
    last_message: 'All the donor files are in the shared folder now.',
    last_message_at: '2026-09-05T16:00:00Z',
    unread_count: 0,
    updated_at: '2026-09-06T09:00:00Z',
  },
]

/** GET /api/admin/staff-chats/:id/messages items per thread, oldest first. */
export const STAFF_MESSAGES: Record<number, StaffMessage[]> = {
  61: [
    staffMsg(6101, 61, 1, 'Rana Aziz', 'Morning. The Mosul distribution group is set up.', '2026-09-15T08:30:00Z'),
    staffMsg(6102, 61, 2, 'Ahmed Faris', 'Can you review the two pending connect requests today?', '2026-09-15T08:50:00Z'),
  ],
  62: [
    staffMsg(6201, 62, 3, 'Zainab Kadhim', 'All the donor files are in the shared folder now.', '2026-09-05T16:00:00Z'),
  ],
}

/** GET /api/admin/staff-directory items: every dashboard account except staff member 1. */
export const STAFF_DIRECTORY: StaffDirectoryEntry[] = [
  { user_id: 2, full_name: 'Ahmed Faris', phone: '+9647700000002', staff_tier: 'admin' },
  { user_id: 3, full_name: 'Zainab Kadhim', phone: '+9647700000003', staff_tier: 'employee' },
  { user_id: 4, full_name: 'Mustafa Hamid', phone: '+9647700000004', staff_tier: 'supervisor' },
]

// ─── Row builders ───
// Positional builders keep each message on one line in the lists above.

/** Builds one donor-chat message row. */
function donorMsg(
  id: number, threadId: number, senderUserId: number, senderRole: number,
  senderName: string, body: string, createdAt: string,
): DonorMessage {
  return { id, thread_id: threadId, sender_user_id: senderUserId, sender_role: senderRole, sender_name: senderName, body, created_at: createdAt }
}

/** Builds one marriage-chat message row. */
function marriageMsg(
  id: number, threadId: number, senderUserId: number, senderRole: MarriageMessage['sender_role'],
  senderName: string, body: string, createdAt: string,
): MarriageMessage {
  return { id, thread_id: threadId, sender_user_id: senderUserId, sender_role: senderRole, sender_name: senderName, body, created_at: createdAt }
}

/** Builds one staff-chat message row. */
function staffMsg(
  id: number, threadId: number, senderUserId: number, senderName: string, body: string, createdAt: string,
): StaffMessage {
  return { id, thread_id: threadId, sender_user_id: senderUserId, sender_name: senderName, body, created_at: createdAt }
}
