// mock-api-routes.mjs — the route table scripts/mock-api.mjs answers from, the
// in-memory state behind it, and the shell and chat-group handlers.
//
// Every reply mirrors the Go handler named beside it: the same status codes,
// envelope and English error text, so a screen's error path looks the same
// against the mock as against the real API. Where the backend has a known gap
// that a later task will close (a duplicate member is a 500, not a 409; see
// "Gaps and traps" in the Phase 6 plan), the mock reproduces TODAY's backend.
//
// Module map:
//   mock-api.mjs             HTTP, scenarios, logging, start-up
//   mock-api-routes.mjs      this file: state, shell, chat groups, route table
//   mock-api-chat-routes.mjs lifecycle/delete for every chat, and the legacy chats
//   mock-api-helpers.mjs     reply envelopes, ids, paging, search
//
// A route is { method, path, handle }. `path` is anchored and captures numeric
// ids; handle({ state, query, body }, ids) returns { status, body }.
import {
  CHAT_GROUP_CONTACT_BLOCKS, CHAT_GROUP_DETAILS, CHAT_GROUP_MESSAGES, CHAT_GROUP_SUMMARIES, CONNECT_REQUESTS,
} from '../src/test/fixtures/chatGroups.ts'
import {
  DONOR_CONTACT_BLOCKS, DONOR_MESSAGES, DONOR_THREADS, MARRIAGE_MESSAGES, MARRIAGE_THREADS,
  STAFF_DIRECTORY, STAFF_MESSAGES, STAFF_THREADS, SUPPORT_THREADS,
} from '../src/test/fixtures/legacyChats.ts'
import { superAdminMatrix } from '../src/test/fixtures/permissions.ts'
import { ADMIN_EVENTS, ADMIN_NOTIFICATIONS, ADMIN_USERS, PENDING_COUNTS } from '../src/test/fixtures/shell.ts'
import {
  applyLifecycle, claimDonorThread, lifecycleRecord, listDonorThreads, listMarriageThreads, listMessages,
  listStaffThreads, postMessage, releaseDonorThread, sendRefusal, startStaffChat, trashThread,
} from './mock-api-chat-routes.mjs'
import {
  STAFF_ID, STAFF_NAME, fail, findGroup, hasBody, matchesQuery, nextId, now, ok, paginate, positiveInt,
} from './mock-api-helpers.mjs'

// ─── State ───────────────────────────────────────────────────────────────

/**
 * A private, mutable copy of every fixture for one server. Writes change this
 * copy only, so two servers (or two tests) never see each other's changes.
 *
 * @returns the state object the route handlers receive as `ctx.state`.
 */
export function createState() {
  return structuredClone({
    lastId: 100_000,
    groupSummaries: CHAT_GROUP_SUMMARIES,
    groups: CHAT_GROUP_DETAILS,
    groupMessages: CHAT_GROUP_MESSAGES,
    groupBlocks: CHAT_GROUP_CONTACT_BLOCKS,
    // Group detail carries only `lifecycle`; the reason and archive flag the
    // lifecycle routes also track live here (plan "Gaps and traps" 2).
    groupLifecycle: {},
    connectRequests: CONNECT_REQUESTS,
    chats: {
      donor: { threads: [...DONOR_THREADS, ...SUPPORT_THREADS], messages: DONOR_MESSAGES },
      marriage: { threads: MARRIAGE_THREADS, messages: MARRIAGE_MESSAGES },
      staff: { threads: STAFF_THREADS, messages: STAFF_MESSAGES },
    },
    donorBlocks: DONOR_CONTACT_BLOCKS,
    supportThreadIds: SUPPORT_THREADS.map((t) => t.id),
  })
}

// ─── Shell: every page ───────────────────────────────────────────────────

const READ_FILTERS = { unread: (n) => n.is_read === 0, read: (n) => n.is_read === 1 }

/** GET /api/admin/notifications — paged, filtered by read_status (handlers/admin_lists.go). */
function listNotifications({ query }) {
  const keep = READ_FILTERS[query.get('read_status')] ?? (() => true)
  return ok(paginate(ADMIN_NOTIFICATIONS.filter(keep), query))
}

/** POST /api/admin/verify-password — any non-blank password matches (handlers/admin_status.go). */
function verifyPassword({ body }) {
  const password = typeof body?.password === 'string' ? body.password.trim() : ''
  if (!password) return { status: 400, body: { success: false, ok: false, error: 'Password required.' } }
  return ok({ ok: true })
}

/** GET /api/admin/users — `{ status, data, pagination }`, q over name and phone (handlers/extras.go). */
function searchUsers({ query }) {
  const matches = matchesQuery(query.get('q'), ['phone', 'full_name'])
  const rows = ADMIN_USERS.filter((u) => matches({ phone: u.phone, full_name: u.profile?.full_name }))
  const { items, ...pagination } = paginate(rows, query)
  return { status: 200, body: { status: 'success', data: items, pagination } }
}

// ─── Chat groups: building and validating (handlers/chat_group_admin.go) ─

const groupNotFound = () => fail(404, 'Group not found.')
const requestNotFound = () => fail(404, 'Connect request not found.')

/** The noun of an auto-generated masked label per role (chatgroups.go autoLabelName). */
const AUTO_LABEL_NOUN = { donor: 'Donor', beneficiary: 'Beneficiary', volunteer: 'Volunteer' }

/** A member row as insertMembers/AddMember store it; `n` numbers a blank masked label. */
function memberRow(state, { kind, input, n }) {
  const masked = kind === 'masked'
  const role = String(input.role_in_group ?? '')
  const typed = String(input.label ?? '').trim()
  return {
    id: nextId(state),
    user_id: Number(input.user_id),
    role_in_group: role,
    masked,
    masked_label: masked ? typed || `${AUTO_LABEL_NOUN[role] ?? 'Member'} ${n}` : '',
  }
}

/** The handler's own check on a create or approve body. @returns an error reply, or null. */
function groupBodyError(body) {
  if (body === null || typeof body !== 'object') return fail(400, 'Invalid JSON.')
  const hasKind = typeof body.kind === 'string' && body.kind.trim() !== ''
  if (!hasKind || !Array.isArray(body.members) || body.members.length === 0) {
    return fail(400, 'kind and at least one member are required.')
  }
  return null
}

/** The store's checks: a known kind, and no user twice (UNIQUE(group_id, user_id) is a 500 today). */
function groupStoreError(body) {
  if (body.kind !== 'masked' && body.kind !== 'team') return fail(400, 'Invalid request.')
  const ids = body.members.map((m) => Number(m.user_id))
  return new Set(ids).size === ids.length ? null : fail(500, 'Database error.')
}

/**
 * Inserts a group and its list row (CreateGroup + insertMembers). A blank
 * masked label is numbered per role within this batch.
 *
 * @returns the new group's id.
 */
function insertGroup(state, body) {
  const id = nextId(state)
  const createdAt = now()
  const counters = {}
  const members = body.members.map((input) => {
    const role = String(input.role_in_group ?? '')
    if (!String(input.label ?? '').trim()) counters[role] = (counters[role] ?? 0) + 1
    return memberRow(state, { kind: body.kind, input, n: counters[role] })
  })
  const title = body.kind === 'team' ? String(body.member_title ?? '') : ''
  state.groups.push({ id, kind: body.kind, member_title: title, created_by_staff_id: STAFF_ID, lifecycle: 'open', created_at: createdAt, members })
  state.groupSummaries.unshift({ id, kind: body.kind, title, unread_count: 0, last_message: '', last_at: createdAt })
  state.groupMessages[id] = []
  state.groupBlocks[id] = []
  return id
}

// ─── Chat groups: handlers ───────────────────────────────────────────────

function createGroup({ state, body }) {
  const error = groupBodyError(body) ?? groupStoreError(body)
  return error ?? ok({ group_id: insertGroup(state, body) })
}

function listConnectRequests({ state, query }) {
  const status = query.get('status')
  return ok({ items: state.connectRequests.filter((r) => !status || r.status === status) })
}

/** GET …/connect-requests/:id — `request` has no context_label; it travels beside it. */
function getConnectRequest({ state }, [id]) {
  const found = state.connectRequests.find((r) => r.id === id)
  if (!found) return requestNotFound()
  const { context_label, ...request } = found
  return ok({ request, context_label })
}

/** POST …/approve — checks in the order the handler and ApproveConnectRequest run them. */
function approveConnectRequest({ state, body }, [id]) {
  const shapeError = groupBodyError(body)
  if (shapeError) return shapeError
  const request = state.connectRequests.find((r) => r.id === id)
  if (!request) return requestNotFound()
  if (request.status !== 'pending') return fail(409, 'This request has already been decided.')
  if (body.kind !== 'masked' && body.kind !== 'team') return fail(400, 'Invalid request.')
  const includesRequester = body.members.some((m) => Number(m.user_id) === request.requester_user_id)
  if (!includesRequester) return fail(400, 'Invalid request.')
  const storeError = groupStoreError(body)
  if (storeError) return storeError
  const groupId = insertGroup(state, body)
  Object.assign(request, { status: 'approved', group_id: groupId, decided_by_staff_id: STAFF_ID })
  return ok({ group_id: groupId })
}

function declineConnectRequest({ state, body }, [id]) {
  const reason = typeof body?.reason === 'string' ? body.reason.trim() : ''
  if (!reason) return fail(400, 'A decline reason is required.')
  const request = state.connectRequests.find((r) => r.id === id)
  if (!request) return requestNotFound()
  if (request.status !== 'pending') return fail(409, 'This request has already been decided.')
  Object.assign(request, { status: 'declined', decline_reason: reason, decided_by_staff_id: STAFF_ID })
  return ok()
}

function getGroup({ state }, [id]) {
  const group = findGroup(state, id)
  return group ? ok({ group }) : groupNotFound()
}

/**
 * POST …/:id/members. UNIQUE(group_id, user_id) also covers a REMOVED row, so
 * re-adding anyone who was ever a member is a 500 today (plan decision D3 will
 * make it a reactivation). A blank masked label continues the role's
 * sequence: members ever added under that role, plus one (AddMember).
 */
function addMember({ state, body }, [id]) {
  const userId = Number(body?.user_id)
  if (!Number.isInteger(userId) || userId <= 0) return fail(400, 'user_id is required.')
  const group = findGroup(state, id)
  if (!group) return groupNotFound()
  if (group.members.some((m) => m.user_id === userId)) return fail(500, 'Database error.')
  const role = String(body.role_in_group ?? '')
  const n = group.members.filter((m) => m.role_in_group === role).length + 1
  group.members.push(memberRow(state, { kind: group.kind, input: body, n }))
  return ok()
}

/** DELETE …/:id/members/:userId — soft removal; 404 unless the member is active. */
function removeMember({ state }, [id, userId]) {
  const member = findGroup(state, id)?.members.find((m) => m.user_id === userId && !m.removed_at)
  if (!member) return groupNotFound()
  member.removed_at = now()
  return ok()
}

/** GET …/:id/messages — after_id, and a limit outside 1-100 means 50 (chatgroups_reads.go). */
function listGroupMessages({ state, query }, [id]) {
  const afterId = positiveInt(query, 'after_id', 0)
  const requested = Number(query.get('limit'))
  const limit = Number.isInteger(requested) && requested >= 1 && requested <= 100 ? requested : 50
  const items = (state.groupMessages[id] ?? []).filter((m) => m.id > afterId).slice(0, limit)
  return ok({ items })
}

/**
 * POST …/:id/messages, sent as staff: sender_member_id 0, and never refused
 * for contact details, because the backend exempts staff senders.
 */
function postGroupMessage({ state, body }, [id]) {
  const group = findGroup(state, id)
  if (!group) return groupNotFound()
  const refused = sendRefusal(lifecycleRecord(state, 'group', id))
  if (refused) return refused
  if (!hasBody(body)) return fail(400, 'Message body is required.')
  const createdAt = now()
  const message = { id: nextId(state), sender_member_id: 0, sender_user_id: STAFF_ID, sender_name: STAFF_NAME, body: body.body, created_at: createdAt }
  ;(state.groupMessages[id] ??= []).push(message)
  const summary = state.groupSummaries.find((s) => s.id === id)
  if (summary) Object.assign(summary, { last_message: body.body, last_at: createdAt })
  return ok({ message_id: message.id })
}

// ─── Route table ─────────────────────────────────────────────────────────

const ID = '(\\d+)'
const route = (method, pattern, handle) => ({ method, path: new RegExp(`^/api/admin/${pattern}$`), handle })

/** Every route the mock answers; anything else gets mock-api.mjs's empty fallback. */
export const ROUTES = [
  // Shell: requested on every page.
  route('GET', 'permissions/me', () => ok({ tier: 'super_admin', permissions: superAdminMatrix() })),
  route('GET', 'pending-counts', () => ({ status: 200, body: { ...PENDING_COUNTS } })),
  route('GET', 'events', ({ query }) => ok({ items: ADMIN_EVENTS.slice(0, positiveInt(query, 'limit', 100)) })),
  route('GET', 'notifications', listNotifications),
  route('GET', 'settings/nav-layout', () => ok({ layout: null })),
  route('GET', 'settings/session-timeout', () => ok({ minutes: 20 })),
  route('POST', 'verify-password', verifyPassword),
  route('GET', 'users', searchUsers),

  // Chat groups and connect requests.
  route('GET', 'chat-groups', ({ state }) => ok({ items: state.groupSummaries })),
  route('POST', 'chat-groups', createGroup),
  route('GET', 'chat-groups/connect-requests', listConnectRequests),
  route('GET', `chat-groups/connect-requests/${ID}`, getConnectRequest),
  route('POST', `chat-groups/connect-requests/${ID}/approve`, approveConnectRequest),
  route('POST', `chat-groups/connect-requests/${ID}/decline`, declineConnectRequest),
  route('GET', `chat-groups/${ID}`, getGroup),
  route('DELETE', `chat-groups/${ID}`, trashThread('group')),
  route('POST', `chat-groups/${ID}/members`, addMember),
  route('DELETE', `chat-groups/${ID}/members/${ID}`, removeMember),
  route('GET', `chat-groups/${ID}/messages`, listGroupMessages),
  route('POST', `chat-groups/${ID}/messages`, postGroupMessage),
  route('GET', `chat-groups/${ID}/contact-blocks`, ({ state }, [id]) => ok({ items: state.groupBlocks[id] ?? [] })),
  route('POST', `chat-groups/${ID}/lifecycle`, applyLifecycle('group')),

  // Donor ↔ owner and support chats.
  route('GET', 'chats', listDonorThreads),
  route('GET', `chats/${ID}/messages`, listMessages('donor')),
  route('POST', `chats/${ID}/messages`, postMessage('donor')),
  route('GET', `chats/${ID}/contact-blocks`, ({ state }, [id]) => ok({ items: state.donorBlocks[id] ?? [] })),
  route('POST', `chats/${ID}/claim`, claimDonorThread),
  route('POST', `chats/${ID}/release`, releaseDonorThread),
  route('POST', `chats/${ID}/lifecycle`, applyLifecycle('donor')),
  route('DELETE', `chats/${ID}`, trashThread('donor')),

  // Marriage chats.
  route('GET', 'marriage/chats', listMarriageThreads),
  route('GET', `marriage/chats/${ID}/messages`, listMessages('marriage')),
  route('POST', `marriage/chats/${ID}/messages`, postMessage('marriage')),
  route('POST', `marriage/chats/${ID}/lifecycle`, applyLifecycle('marriage')),
  route('DELETE', `marriage/chats/${ID}`, trashThread('marriage')),

  // Staff chats.
  route('GET', 'staff-directory', () => ok({ items: STAFF_DIRECTORY })),
  route('GET', 'staff-chats', listStaffThreads),
  route('POST', 'staff-chats/start', startStaffChat),
  route('GET', `staff-chats/${ID}/messages`, listMessages('staff')),
  route('POST', `staff-chats/${ID}/messages`, postMessage('staff')),
  route('POST', `staff-chats/${ID}/lifecycle`, applyLifecycle('staff')),
  route('DELETE', `staff-chats/${ID}`, trashThread('staff')),
]
