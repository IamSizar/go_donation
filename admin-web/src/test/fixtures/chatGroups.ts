/**
 * chatGroups.ts — chat groups as staff see them through /api/admin/chat-groups.
 *
 * Two groups, one of each kind migration 120 allows (CHECK kind IN
 * ('masked', 'team')):
 *   - MASKED (41): donors and a beneficiary who see each other only as labels.
 *     It has a removed member, two refused contact-sharing attempts, and
 *     enough messages to page through with after_id/limit.
 *   - TEAM (42): a titled working group of volunteers, with no labels.
 * And connect requests in every status: pending, approved and declined.
 *
 * The people match src/test/fixtures/shell.ts's users list (101 Layla Hassan,
 * 103 Sara Ali, 104 Omar Khalid, 105 Yusuf Kareem, 106 Noor Jabbar), and staff
 * member 1 is the signed-in mock session. Each type names the Go struct whose
 * JSON it mirrors. Every person, message and number is invented. No runtime
 * imports, so Node can load this file with --experimental-strip-types.
 */

// ─── Types (backend/internal/chatgroups) ───

/** The two kinds of group. */
export type ChatGroupKind = 'masked' | 'team'

/** One row of GET /api/admin/chat-groups (chatgroups_reads.go, GroupSummary). */
export type ChatGroupSummary = {
  id: number
  kind: ChatGroupKind
  /** Team groups only; '' for a masked group. */
  title: string
  unread_count: number
  last_message: string
  last_at: string
}

/**
 * One roster row (chatgroups_admin.go, GroupMember). role_in_group is free
 * text: migration 120 puts no CHECK on it, and the backend tests use 'donor'.
 */
export type ChatGroupMember = {
  id: number
  user_id: number
  role_in_group: string
  masked: boolean
  masked_label: string
  removed_at?: string
}

/** GET /api/admin/chat-groups/:id → `group` (chatgroups.go Group + chatgroups_admin.go GroupDetail). */
export type ChatGroupDetail = {
  id: number
  kind: ChatGroupKind
  /** Team groups only; a masked group ignores it and stores ''. */
  member_title: string
  created_by_staff_id: number
  lifecycle: 'open' | 'paused' | 'ended'
  created_at: string
  members: ChatGroupMember[]
}

/**
 * One row of GET /api/admin/chat-groups/:id/messages, oldest first
 * (chatgroups.go, AdminGroupMessage). A staff message has sender_member_id 0,
 * because staff are not members (COALESCE(mem.id, 0) in chatgroups_reads.go).
 */
export type ChatGroupMessage = {
  id: number
  sender_member_id: number
  sender_user_id: number
  sender_name: string
  body: string
  created_at: string
}

/** One row of GET /api/admin/chat-groups/:id/contact-blocks (chatgroups_admin.go, GroupContactBlock). */
export type ChatGroupContactBlock = {
  id: number
  group_id: number
  sender_user_id: number
  sender_name: string | null
  kind: 'phone' | 'email' | 'both'
  match_count: number
  redacted_body: string
  created_at: string
}

/**
 * One row of GET /api/admin/chat-groups/connect-requests
 * (chatgroups_connect.go ConnectRequest, plus the handler's context_label).
 */
export type ConnectRequest = {
  id: number
  requester_user_id: number
  context_type: 'donation' | 'case'
  context_id: number
  target_hint?: number
  message: string
  group_id?: number
  status: 'pending' | 'approved' | 'declined'
  decline_reason?: string
  decided_by_staff_id?: number
  created_at: string
  context_label: string
}

// ─── Groups ───

/** The masked group's id. */
export const MASKED_GROUP_ID = 41

/** The team group's id. */
export const TEAM_GROUP_ID = 42

/** GET /api/admin/chat-groups items, most recent activity first. */
export const CHAT_GROUP_SUMMARIES: ChatGroupSummary[] = [
  {
    id: TEAM_GROUP_ID,
    kind: 'team',
    title: 'Distribution volunteers — Mosul',
    unread_count: 0,
    last_message: 'Thanks both. Report any shortages here.',
    last_at: '2026-09-14T09:00:00Z',
  },
  {
    id: MASKED_GROUP_ID,
    kind: 'masked',
    title: '',
    unread_count: 0,
    last_message: 'The office will confirm the delivery details here.',
    last_at: '2026-09-12T08:00:00Z',
  },
]

/** GET /api/admin/chat-groups/:id `group`, one entry per group. */
export const CHAT_GROUP_DETAILS: ChatGroupDetail[] = [
  {
    id: MASKED_GROUP_ID,
    kind: 'masked',
    member_title: '',
    created_by_staff_id: 1,
    lifecycle: 'open',
    created_at: '2026-09-10T09:00:00Z',
    members: [
      { id: 701, user_id: 101, role_in_group: 'donor', masked: true, masked_label: 'Donor 1' },
      { id: 702, user_id: 103, role_in_group: 'beneficiary', masked: true, masked_label: 'Beneficiary' },
      {
        id: 703,
        user_id: 104,
        role_in_group: 'donor',
        masked: true,
        masked_label: 'Donor 2',
        removed_at: '2026-09-12T16:00:00Z',
      },
    ],
  },
  {
    id: TEAM_GROUP_ID,
    kind: 'team',
    member_title: 'Distribution volunteers — Mosul',
    created_by_staff_id: 1,
    lifecycle: 'open',
    created_at: '2026-09-13T16:30:00Z',
    members: [
      { id: 711, user_id: 105, role_in_group: 'volunteer', masked: false, masked_label: '' },
      { id: 712, user_id: 106, role_in_group: 'volunteer', masked: false, masked_label: '' },
    ],
  },
]

// ─── Messages and refusals ───

/** GET /api/admin/chat-groups/:id/messages items per group, oldest first. */
export const CHAT_GROUP_MESSAGES: Record<number, ChatGroupMessage[]> = {
  [MASKED_GROUP_ID]: [
    msg(8101, 701, 101, 'Layla Hassan', 'Hello, I would like to help with the school supplies.', '2026-09-10T09:05:00Z'),
    msg(8102, 702, 103, 'Sara Ali', 'Thank you so much. The children start school on the 20th.', '2026-09-10T09:12:00Z'),
    msg(8103, 0, 1, 'Rana Aziz', 'I have added a second donor who offered to share the cost.', '2026-09-11T10:00:00Z'),
    msg(8104, 703, 104, 'Omar Khalid', 'Happy to cover half. Where should I send it?', '2026-09-11T10:30:00Z'),
    msg(8105, 702, 103, 'Sara Ali', 'The office will confirm the delivery details here.', '2026-09-12T08:00:00Z'),
  ],
  [TEAM_GROUP_ID]: [
    msg(8201, 711, 105, 'Yusuf Kareem', 'The truck reaches the warehouse at 8.', '2026-09-13T17:00:00Z'),
    msg(8202, 712, 106, 'Noor Jabbar', 'I will bring the checklists.', '2026-09-13T17:20:00Z'),
    msg(8203, 0, 1, 'Rana Aziz', 'Thanks both. Report any shortages here.', '2026-09-14T09:00:00Z'),
  ],
}

/**
 * GET /api/admin/chat-groups/:id/contact-blocks items per group, newest
 * first. The team group is clean, so it shows the empty state.
 */
export const CHAT_GROUP_CONTACT_BLOCKS: Record<number, ChatGroupContactBlock[]> = {
  [MASKED_GROUP_ID]: [
    {
      id: 612,
      group_id: MASKED_GROUP_ID,
      sender_user_id: 104,
      sender_name: 'Omar Khalid',
      kind: 'both',
      match_count: 2,
      redacted_body: 'My number is ••• or email ••• if that is easier',
      created_at: '2026-09-11T10:27:00Z',
    },
    {
      id: 611,
      group_id: MASKED_GROUP_ID,
      sender_user_id: 104,
      sender_name: 'Omar Khalid',
      kind: 'phone',
      match_count: 1,
      redacted_body: 'Just call me on ••• and we can sort it out',
      created_at: '2026-09-11T10:25:00Z',
    },
  ],
  [TEAM_GROUP_ID]: [],
}

// ─── Connect requests ───

/**
 * GET /api/admin/chat-groups/connect-requests items, newest first.
 * context_label follows resolveConnectContext in handlers/chat_group_admin.go:
 * `Donation of <amount> to "<campaign>"` or `Case <code> — <title>`.
 */
export const CONNECT_REQUESTS: ConnectRequest[] = [
  {
    id: 32,
    requester_user_id: 105,
    context_type: 'case',
    context_id: 2304,
    message: 'I can deliver the wheelchair myself if that helps.',
    status: 'pending',
    created_at: '2026-09-15T09:10:00Z',
    context_label: 'Case HC-2304 — Wheelchair for an elderly father',
  },
  {
    id: 31,
    requester_user_id: 102,
    context_type: 'case',
    context_id: 2291,
    message: 'I would like to support this family directly.',
    status: 'pending',
    created_at: '2026-09-15T08:30:00Z',
    context_label: 'Case HC-2291 — School supplies for three children',
  },
  {
    id: 30,
    requester_user_id: 101,
    context_type: 'donation',
    context_id: 7702,
    message: 'Could I speak with the family I donated to?',
    group_id: MASKED_GROUP_ID,
    status: 'approved',
    decided_by_staff_id: 1,
    created_at: '2026-09-09T15:00:00Z',
    context_label: 'Donation of 75000 to "Back to school"',
  },
  {
    id: 29,
    requester_user_id: 104,
    context_type: 'donation',
    context_id: 7650,
    target_hint: 103,
    message: 'Please give them my phone number.',
    status: 'declined',
    decline_reason: 'We cannot share contact details. You can follow the case updates instead.',
    decided_by_staff_id: 1,
    created_at: '2026-09-08T11:00:00Z',
    context_label: 'Donation of 25000 to "General fund"',
  },
]

// ─── Helpers ───

/** Builds one admin message row; keeps the lists above one line per message. */
function msg(
  id: number,
  senderMemberId: number,
  senderUserId: number,
  senderName: string,
  body: string,
  createdAt: string,
): ChatGroupMessage {
  return {
    id,
    sender_member_id: senderMemberId,
    sender_user_id: senderUserId,
    sender_name: senderName,
    body,
    created_at: createdAt,
  }
}
