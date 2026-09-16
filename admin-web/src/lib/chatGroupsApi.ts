/**
 * chatGroupsApi.ts — typed calls for the chat-group admin routes.
 *
 * WHAT IT CONTAINS
 * One function per route under /api/admin/chat-groups that staff screens use
 * (backend/cmd/server/main.go, handlers/chat_group_admin.go), plus the JSON
 * types those routes answer with. Every call goes through the shared `api`
 * axios instance, so the Bearer header, the delete-password prompt and the
 * sign-out on 401 apply exactly as they do everywhere else.
 *
 * HOW IT FITS
 * Phase 6a (ChatGroupsPage, CreateGroupDialog) uses listGroups and
 * createGroup. The rest is here for 6b (group detail, roster, messages,
 * contact blocks, lifecycle) and 6c (the connect-request inbox), so those
 * screens do not each re-type the same envelopes.
 *
 * Failures are NOT caught here: every function rejects with the axios error,
 * and the caller turns it into words with describeChatGroupError
 * (lib/chatGroupErrors.ts), which knows the chat-group refusal codes.
 *
 * The types mirror the Go structs named beside them and match the mock API's
 * fixtures in src/test/fixtures/chatGroups.ts.
 */
import { api } from './api'

// ─── Types ───

/** The two kinds of group (CHECK kind IN ('masked', 'team'), migration 120). */
export type ChatGroupKind = 'masked' | 'team'

/** Where a group is in its life (chatlifecycle). */
export type ChatGroupLifecycle = 'open' | 'paused' | 'ended'

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

/** One member as a create, approve or add-member request sends it. */
export type ChatGroupMemberInput = {
  user_id: number
  role_in_group: string
  /** Masked groups only. '' lets the server number it ("Donor 1"). */
  label: string
}

/** The body of POST /api/admin/chat-groups and of a connect-request approval. */
export type CreateGroupBody = {
  kind: ChatGroupKind
  /** Team groups only; a masked group sends ''. */
  member_title: string
  members: ChatGroupMemberInput[]
}

/** One roster row (chatgroups_admin.go, GroupMember). */
export type ChatGroupMember = {
  id: number
  user_id: number
  /** The member's real name (#111). null when the profile has none. */
  full_name: string | null
  role_in_group: string
  masked: boolean
  masked_label: string
  removed_at?: string
}

/** GET /api/admin/chat-groups/:id → `group` (chatgroups_admin.go, GroupDetail). */
export type ChatGroupDetail = {
  id: number
  kind: ChatGroupKind
  member_title: string
  created_by_staff_id: number
  lifecycle: ChatGroupLifecycle
  /** Staff's reason for pausing or ending, shown to members; null when none (#111). */
  lifecycle_reason: string | null
  /** Hidden from the members' own lists (#111). */
  is_archived: boolean
  created_at: string
  members: ChatGroupMember[]
}

/** The lifecycle fields #111 sends beside `group`, not inside it. */
type LifecycleFields = Pick<ChatGroupDetail, 'lifecycle' | 'lifecycle_reason' | 'is_archived'>

/**
 * One message, oldest first (chatgroups.go, AdminGroupMessage). A staff
 * message has sender_member_id 0, because staff are not members.
 */
export type ChatGroupMessage = {
  id: number
  sender_member_id: number
  sender_user_id: number
  sender_name: string
  body: string
  created_at: string
}

/** One refused contact-sharing attempt (chatgroups_admin.go, GroupContactBlock). */
export type ChatGroupContactBlock = {
  id: number
  group_id: number
  sender_user_id: number
  sender_name: string | null
  kind: 'phone' | 'email' | 'both'
  match_count: number
  /** The message with every contact detail already replaced by "•••". */
  redacted_body: string
  created_at: string
}

/** A connect request's status (CHECK status IN (...), migration 120). */
export type ConnectRequestStatus = 'pending' | 'approved' | 'declined'

/** One row of GET …/connect-requests (chatgroups_connect.go, plus context_label). */
export type ConnectRequest = {
  id: number
  requester_user_id: number
  context_type: 'donation' | 'case'
  context_id: number
  target_hint?: number
  message: string
  group_id?: number
  status: ConnectRequestStatus
  decline_reason?: string
  decided_by_staff_id?: number
  created_at: string
  context_label: string
  /**
   * The requester's profile name. The key is ABSENT unless the caller may view
   * sensitive data (per user) and the requester has a profile (D6), so a
   * screen must fall back to the requester's id.
   */
  requester_name?: string
  /**
   * The other party: the person the request's context belongs to — the case's
   * owner, or the owner of the campaign the donation went to. ABSENT when the
   * request has none (a donation to the general fund) or the server could not
   * resolve one. The server adds this person to the group itself on approve;
   * the dialog pre-fills them so staff can see and change who that will be.
   */
  other_party_user_id?: number
  /**
   * The other party's profile name. Like requester_name, the key is ABSENT
   * unless the caller may view sensitive data (per user, D6) — the id is not
   * gated, the name is — so a screen must fall back to the id.
   */
  other_party_name?: string
}

/**
 * GET …/connect-requests/:id: the request, with its label beside it. The
 * backend's `request` is the list item's full shape, context_label included.
 */
export type ConnectRequestDetail = {
  request: Omit<ConnectRequest, 'context_label'> & { context_label?: string }
  context_label: string
}

/** The actions POST …/:id/lifecycle accepts (chatlifecycle.Apply). */
export type ChatGroupLifecycleAction = 'end' | 'pause' | 'resume' | 'archive' | 'unarchive'

// ─── Constants ───

const BASE = '/api/admin/chat-groups'

/**
 * The largest page GET …/:id/messages serves. A limit outside 1–100 silently
 * becomes 50 on the server (chatgroups_reads.go), so a caller asking for more
 * would get fewer rows than it expected and stop paging too early.
 */
export const GROUP_MESSAGES_PAGE_MAX = 100

type Items<T> = { items?: T[] }

// ─── Groups ───

/**
 * Lists every chat group, most recent activity first. The route has no
 * paging. Needs messages:view.
 *
 * @returns the groups, or [] when there are none.
 * @throws  the axios error when the request fails.
 */
export async function listGroups(): Promise<ChatGroupSummary[]> {
  const res = await api.get<Items<ChatGroupSummary>>(BASE)
  return res.data.items ?? []
}

/**
 * Creates a group with its first members. Needs messages:add.
 *
 * @param body  kind, title (team only) and members; see {@link CreateGroupBody}.
 * @returns     the new group's id.
 * @throws      the axios error when the server refuses it, e.g. 400
 *              guest_member_not_allowed or 409 group_label_conflict.
 */
export async function createGroup(body: CreateGroupBody): Promise<number> {
  const res = await api.post<{ group_id: number }>(BASE, body)
  return res.data.group_id
}

/**
 * Reads one group with its whole roster, removed members included. Needs
 * messages:view; a masked group also needs sensitive data.
 *
 * @throws the axios error; 404 group_not_found, 403 sensitive_data_required.
 */
export async function getGroup(groupId: number): Promise<ChatGroupDetail> {
  // #111 sends the lifecycle fields at the top level (mergeChatLifecycle), so
  // they are folded into the group here and 6b reads one object.
  const res = await api.get<{ group: ChatGroupDetail } & LifecycleFields>(`${BASE}/${groupId}`)
  const { group, lifecycle, lifecycle_reason, is_archived } = res.data
  return { ...group, lifecycle, lifecycle_reason: lifecycle_reason ?? null, is_archived: is_archived === true }
}

/**
 * Adds one member. Needs messages:edit.
 *
 * Re-adding a REMOVED member reactivates their old membership (decision D3):
 * their old label and role are kept, and `member.role_in_group` and
 * `member.label` are ignored.
 *
 * @throws the axios error: 409 group_member_conflict when they are already
 *         active; 409 group_label_conflict when the label, or a reactivated
 *         member's old label, is taken; 400 guest_member_not_allowed or
 *         group_label_contact; 404 group_not_found.
 */
export async function addGroupMember(groupId: number, member: ChatGroupMemberInput): Promise<void> {
  await api.post(`${BASE}/${groupId}/members`, member)
}

/**
 * Removes one active member. Needs messages:edit. The request interceptor in
 * lib/api.ts asks the operator for their password first, as for every admin
 * DELETE.
 *
 * @throws the axios error (404 group_not_found when the user is not an active
 *         member), or an axios cancel when the operator dismisses the
 *         password prompt.
 */
export async function removeGroupMember(groupId: number, userId: number): Promise<void> {
  await api.delete(`${BASE}/${groupId}/members/${userId}`)
}

// ─── Messages and contact blocks ───

/**
 * Reads one page of messages, oldest first.
 *
 * @param page.afterId  only messages with a larger id; omit for the start.
 * @param page.limit    1–{@link GROUP_MESSAGES_PAGE_MAX}; the server's 50 when omitted.
 * @throws              the axios error; 404 group_not_found for a missing group.
 */
export async function listGroupMessages(
  groupId: number,
  page: { afterId?: number; limit?: number } = {},
): Promise<ChatGroupMessage[]> {
  const params: Record<string, number> = {}
  if (page.afterId !== undefined) params.after_id = page.afterId
  if (page.limit !== undefined) params.limit = page.limit
  const res = await api.get<Items<ChatGroupMessage>>(`${BASE}/${groupId}/messages`, { params })
  return res.data.items ?? []
}

/**
 * Reads a group's whole history by paging on after_id, for export (E3).
 *
 * The route sends no has_more flag, so paging stops at the first short page.
 * It also stops if the last id does not move past the cursor, so a server
 * that ignored after_id could never loop this forever.
 *
 * @param pageSize  rows per request, clamped to 1–{@link GROUP_MESSAGES_PAGE_MAX}.
 * @returns         every message, oldest first.
 * @throws          the axios error of the first page that fails (404
 *                  group_not_found for a missing group).
 */
export async function fetchAllGroupMessages(
  groupId: number,
  pageSize: number = GROUP_MESSAGES_PAGE_MAX,
): Promise<ChatGroupMessage[]> {
  const limit = Math.min(GROUP_MESSAGES_PAGE_MAX, Math.max(1, Math.floor(pageSize)))
  const all: ChatGroupMessage[] = []
  let afterId = 0
  for (;;) {
    const page = await listGroupMessages(groupId, { afterId, limit })
    all.push(...page)
    const lastId = page.at(-1)?.id ?? afterId
    if (page.length < limit || lastId <= afterId) return all
    afterId = lastId
  }
}

/**
 * Sends a message into the group as the signed-in staff member. Needs
 * messages:add.
 *
 * @returns the new message's id.
 * @throws  the axios error; 422 contact_details_blocked, or 409
 *          chat_lifecycle_closed (with `lifecycle_reason`) when the group is
 *          paused or ended.
 */
export async function postGroupMessage(groupId: number, body: string): Promise<number> {
  const res = await api.post<{ message_id: number }>(`${BASE}/${groupId}/messages`, { body })
  return res.data.message_id
}

/**
 * Lists the refused contact-sharing attempts in one group, newest first.
 *
 * @throws the axios error; 404 group_not_found for a missing group.
 */
export async function listGroupContactBlocks(groupId: number): Promise<ChatGroupContactBlock[]> {
  const res = await api.get<Items<ChatGroupContactBlock>>(`${BASE}/${groupId}/contact-blocks`)
  return res.data.items ?? []
}

// ─── Lifecycle ───

/**
 * Pauses, resumes, ends, archives or un-archives a group, with the same body
 * ChatLifecycleControls sends. Needs messages:edit.
 *
 * @param reason  shown to members in place of their message box; may be ''.
 * @throws        the axios error; 409 when the transition is not allowed.
 */
export async function applyGroupLifecycle(
  groupId: number,
  action: ChatGroupLifecycleAction,
  reason = '',
): Promise<void> {
  await api.post(`${BASE}/${groupId}/lifecycle`, { action, reason })
}

/**
 * Moves a group to the Trash. Needs messages:delete; the interceptor asks for
 * the operator's password first.
 *
 * @throws the axios error, or an axios cancel when the prompt is dismissed.
 */
export async function trashGroup(groupId: number): Promise<void> {
  await api.delete(`${BASE}/${groupId}`)
}

// ─── Connect requests ───

/**
 * Lists connect requests, newest first. The route has no paging. Needs
 * messages:view.
 *
 * @param status  only requests in this status; every status when omitted.
 * @throws        the axios error when the request fails.
 */
export async function listConnectRequests(status?: ConnectRequestStatus): Promise<ConnectRequest[]> {
  const config = status ? { params: { status } } : undefined
  const res = await api.get<Items<ConnectRequest>>(`${BASE}/connect-requests`, config)
  return res.data.items ?? []
}

/**
 * Reads one connect request.
 *
 * @throws the axios error; a 404 with no code when it does not exist, which
 *         describeConnectRequestError (lib/chatGroupErrors.ts) translates.
 */
export async function getConnectRequest(requestId: number): Promise<ConnectRequestDetail> {
  const res = await api.get<ConnectRequestDetail>(`${BASE}/connect-requests/${requestId}`)
  return { request: res.data.request, context_label: res.data.context_label }
}

/**
 * Approves a pending request by creating its group. The requester MUST be
 * one of `body.members`, or the server answers 400. Needs messages:edit.
 *
 * @returns the new group's id.
 * @throws  the axios error; 409 connect_request_decided when already decided,
 *          or a 404 with no code when the request does not exist.
 */
export async function approveConnectRequest(requestId: number, body: CreateGroupBody): Promise<number> {
  const res = await api.post<{ group_id: number }>(`${BASE}/connect-requests/${requestId}/approve`, body)
  return res.data.group_id
}

/**
 * Declines a pending request. Needs messages:edit.
 *
 * @param reason  required by the server; shown to the requester.
 * @throws        the axios error; 400 when the reason is blank, 409
 *                connect_request_decided when decided, 404 with no code
 *                when the request does not exist.
 */
export async function declineConnectRequest(requestId: number, reason: string): Promise<void> {
  await api.post(`${BASE}/connect-requests/${requestId}/decline`, { reason })
}
