// mock-api-chat-routes.mjs — what every chat system shares in the mock API, and
// the three chat systems that predate chat groups.
//
//   Lifecycle and delete  POST …/:id/lifecycle and DELETE …/:id, for donor,
//                         marriage, staff and group threads alike
//                         (handlers/admin_chat_lifecycle.go,
//                         handlers/chat_lifecycle_gate.go, internal/chatlifecycle)
//   Legacy chats          donor ↔ owner and support (handlers/chat.go),
//                         marriage (handlers/marriage_chat.go),
//                         staff ↔ staff (handlers/staff_chat.go)
//
// scripts/mock-api-routes.mjs puts these handlers into its route table. The
// seam is "chat threads in general" here versus "the shell and chat groups"
// there, which keeps both files readable in one sitting.
//
// The 404 text is handlers/chat.go's and staff_chat.go's. The legacy handlers'
// empty-body 400 text was not checked, so it borrows the chat-group handler's.
import { STAFF_DIRECTORY } from '../src/test/fixtures/legacyChats.ts'
import {
  STAFF_ID, STAFF_NAME, fail, findGroup, hasBody, matchesQuery, nextId, now, ok,
} from './mock-api-helpers.mjs'

// ─── Lifecycle ───────────────────────────────────────────────────────────

const LIFECYCLE_ACTIONS = ['end', 'pause', 'resume', 'archive', 'unarchive']
const PAUSED_TEXT =
  'This conversation has been paused by our team, so new messages cannot be sent right now. You can still read it, and our team can resume it.'
const ENDED_TEXT =
  'This conversation has been closed by our team. You can still read it, but no new messages can be sent.'

/**
 * The record that holds a thread's `lifecycle`, `lifecycle_reason` and
 * `is_archived`. A legacy thread row carries them itself; a chat group's live
 * in `state.groupLifecycle`, because group detail has only `lifecycle`.
 *
 * @param {'donor' | 'marriage' | 'staff' | 'group'} kind
 * @returns the mutable record, or null when the thread does not exist.
 */
export function lifecycleRecord(state, kind, id) {
  if (kind !== 'group') return findThread(state, kind, id) ?? null
  const group = findGroup(state, id)
  if (!group) return null
  state.groupLifecycle[id] ??= { lifecycle: group.lifecycle, lifecycle_reason: null, is_archived: false }
  return state.groupLifecycle[id]
}

/**
 * The 409 a send to a paused or ended thread gets (refuseIfNotSendable), with
 * staff's reason appended the way chatlifecycle's UserMessage appends it.
 *
 * @returns the refusal reply, or null when the thread accepts messages.
 */
export function sendRefusal(record) {
  if (record.lifecycle === 'open') return null
  const base = record.lifecycle === 'ended' ? ENDED_TEXT : PAUSED_TEXT
  const reason = (record.lifecycle_reason ?? '').trim()
  return fail(409, reason ? `${base} Reason: ${reason}` : base, {
    code: 'chat_lifecycle_closed',
    lifecycle: record.lifecycle,
    lifecycle_reason: record.lifecycle_reason,
  })
}

/**
 * Applies one known action to a record, following chatlifecycle.Apply: ending
 * is final, ending twice is a no-op, and only a paused thread resumes.
 *
 * @returns an error reply, or null when the record was updated.
 */
function transition(record, action, reason) {
  if (action === 'archive' || action === 'unarchive') {
    record.is_archived = action === 'archive'
    return null
  }
  const ended = record.lifecycle === 'ended'
  if (action === 'end') {
    if (!ended) Object.assign(record, { lifecycle: 'ended', lifecycle_reason: reason || null })
    return null
  }
  if (ended) return fail(409, 'This chat has been ended. Ending is final — start a new conversation instead.')
  if (action === 'pause') {
    Object.assign(record, { lifecycle: 'paused', lifecycle_reason: reason || null })
    return null
  }
  if (record.lifecycle !== 'paused') return fail(409, 'This chat is not paused, so it cannot be resumed.')
  Object.assign(record, { lifecycle: 'open', lifecycle_reason: null })
  return null
}

/**
 * The POST …/:id/lifecycle handler for one chat system. An unknown action is
 * refused before the thread is looked up, as in chatlifecycle.Apply.
 *
 * @param {'donor' | 'marriage' | 'staff' | 'group'} kind
 */
export function applyLifecycle(kind) {
  return ({ state, body }, [id]) => {
    if (body === null || typeof body !== 'object') return fail(400, 'Invalid JSON body.')
    const action = String(body.action ?? '')
    if (!LIFECYCLE_ACTIONS.includes(action)) {
      return fail(400, 'Unknown action. Use end, pause, resume, archive or unarchive.')
    }
    const record = lifecycleRecord(state, kind, id)
    if (!record) return fail(404, 'Chat not found.')
    const error = transition(record, action, String(body.reason ?? '').trim())
    if (error) return error
    if (kind === 'group') findGroup(state, id).lifecycle = record.lifecycle
    return ok({ id, kind, lifecycle: record.lifecycle, reason: record.lifecycle_reason, is_archived: record.is_archived })
  }
}

/**
 * The DELETE …/:id handler for one chat system. The thread leaves every list;
 * in the real API it goes to the Trash.
 *
 * @param {'donor' | 'marriage' | 'staff' | 'group'} kind
 */
export function trashThread(kind) {
  return ({ state }, [id]) => {
    const list = kind === 'group' ? state.groups : state.chats[kind].threads
    const index = list.findIndex((t) => t.id === id)
    if (index === -1) return fail(404, 'Chat not found.')
    list.splice(index, 1)
    if (kind === 'group') state.groupSummaries = state.groupSummaries.filter((s) => s.id !== id)
    return ok({ id, trashed: true, kind })
  }
}

// ─── Legacy thread lists ────────────────────────────────────────────────

/** The sender_role a staff reply is stored with: chat.RoleSupport, or marriage's "staff". Staff chat has none. */
const STAFF_SENDER_ROLE = { donor: 0, marriage: 'staff' }

function findThread(state, kind, id) {
  return state.chats[kind].threads.find((t) => t.id === id)
}

/** GET /api/admin/chats — `?kind=support` lists support threads; anything else, donor ↔ owner ones. */
export function listDonorThreads({ state, query }) {
  const wantSupport = query.get('kind') === 'support'
  const matches = matchesQuery(query.get('q'), ['donor_name', 'owner_name', 'campaign_title'])
  const items = state.chats.donor.threads.filter(
    (t) => state.supportThreadIds.includes(t.id) === wantSupport && matches(t),
  )
  return ok({ items })
}

/** GET /api/admin/marriage/chats, searched by `q`. */
export function listMarriageThreads({ state, query }) {
  const matches = matchesQuery(query.get('q'), ['requester_name', 'owner_name', 'profile_code'])
  return ok({ items: state.chats.marriage.threads.filter(matches) })
}

/** GET /api/admin/staff-chats — archived threads are included only with `include_archived=1`. */
export function listStaffThreads({ state, query }) {
  const includeArchived = query.get('include_archived') === '1'
  return ok({ items: state.chats.staff.threads.filter((t) => includeArchived || !t.is_archived) })
}

// ─── Legacy messages ────────────────────────────────────────────────────

/**
 * The GET …/:id/messages handler for one legacy system. Donor and marriage
 * replies also carry the thread's status (their AdminMessages handlers).
 *
 * @param {'donor' | 'marriage' | 'staff'} kind
 */
export function listMessages(kind) {
  return ({ state }, [id]) => {
    const thread = findThread(state, kind, id)
    if (!thread) return fail(404, 'Chat not found.')
    const items = state.chats[kind].messages[id] ?? []
    return kind === 'staff' ? ok({ items }) : ok({ status: thread.status, items })
  }
}

/**
 * The POST …/:id/messages handler for one legacy system, sending as the mock
 * staff member and answering `{ success, message }` like the Go handlers.
 * A paused or ended thread refuses staff too.
 *
 * @param {'donor' | 'marriage' | 'staff'} kind
 */
export function postMessage(kind) {
  return ({ state, body }, [id]) => {
    const thread = findThread(state, kind, id)
    if (!thread) return fail(404, 'Chat not found.')
    const refused = sendRefusal(thread)
    if (refused) return refused
    if (!hasBody(body)) return fail(400, 'Message body is required.')
    const createdAt = now()
    const message = { id: nextId(state), thread_id: id, sender_user_id: STAFF_ID, sender_name: STAFF_NAME, body: body.body, created_at: createdAt }
    if (kind in STAFF_SENDER_ROLE) message.sender_role = STAFF_SENDER_ROLE[kind]
    ;(state.chats[kind].messages[id] ??= []).push(message)
    Object.assign(thread, { last_message: body.body, last_message_at: createdAt, updated_at: createdAt })
    if (typeof thread.message_count === 'number') thread.message_count += 1
    return ok({ message })
  }
}

// ─── Donor-chat claim and staff-chat start ──────────────────────────────

/** POST /api/admin/chats/:id/claim — the mock staff member becomes the responsible staff member. */
export function claimDonorThread({ state }, [id]) {
  const thread = findThread(state, 'donor', id)
  if (!thread) return fail(404, 'Chat not found.')
  if (thread.assigned_staff_user_id && thread.assigned_staff_user_id !== STAFF_ID) {
    return fail(409, 'This chat is already claimed by another staff member.')
  }
  Object.assign(thread, { assigned_staff_user_id: STAFF_ID, assigned_staff_name: STAFF_NAME })
  return ok({ thread_id: id, assigned_staff_user_id: STAFF_ID })
}

/** POST /api/admin/chats/:id/release — the thread has no responsible staff member again. */
export function releaseDonorThread({ state }, [id]) {
  const thread = findThread(state, 'donor', id)
  if (!thread) return fail(404, 'Chat not found.')
  Object.assign(thread, { assigned_staff_user_id: null, assigned_staff_name: null })
  return ok({ thread_id: id })
}

/** POST /api/admin/staff-chats/start — gets or creates a thread with another staff member. */
export function startStaffChat({ state, body }) {
  const userId = Number(body?.user_id)
  if (!Number.isInteger(userId) || userId <= 0) return fail(400, 'user_id is required.')
  if (userId === STAFF_ID) return fail(400, 'You cannot message yourself.')
  const existing = state.chats.staff.threads.find((t) => t.other_user_id === userId)
  if (existing) return ok({ thread_id: existing.id })
  const other = STAFF_DIRECTORY.find((d) => d.user_id === userId)
  const thread = {
    id: nextId(state), other_user_id: userId, other_name: other?.full_name ?? null,
    other_staff_tier: other?.staff_tier ?? null, last_message: null, last_message_at: null,
    unread_count: 0, updated_at: now(), lifecycle: 'open', lifecycle_reason: null, is_archived: false,
  }
  state.chats.staff.threads.unshift(thread)
  state.chats.staff.messages[thread.id] = []
  return ok({ thread_id: thread.id })
}
