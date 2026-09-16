/**
 * chatGroupDetailKit.ts — what the chat-group detail tests share (Phase 6b).
 *
 * WHAT IT CONTAINS
 *   - The detail, messages and contact-block URLs for a group id.
 *   - detailOf(): a fixture group as the #111 route sends it, folded the way
 *     chatGroupsApi.getGroup folds it (full_name per member, lifecycle fields).
 *   - serveGroup(): registers every read the page makes for one group.
 *   - refusal(): an error reply carrying a chat-group refusal code.
 *
 * The fixtures are src/test/fixtures/chatGroups.ts, which the mock API serves
 * too, so a screen tested here looks the same against `npm run mock-api`.
 */
import type { ChatGroupDetail, ChatGroupMessage } from '../lib/chatGroupsApi'
import { CHAT_GROUP_CONTACT_BLOCKS, CHAT_GROUP_DETAILS, CHAT_GROUP_MESSAGES } from './fixtures/chatGroups'
import { ADMIN_USERS } from './fixtures/shell'
import type { MockApi, MockReply } from './mockApi'

// ─── URLs ───

/** GET/DELETE /api/admin/chat-groups/:id */
export const groupUrl = (id: number) => `/api/admin/chat-groups/${id}`
/** GET/POST …/:id/messages */
export const messagesUrl = (id: number) => `${groupUrl(id)}/messages`
/** GET …/:id/contact-blocks */
export const blocksUrl = (id: number) => `${groupUrl(id)}/contact-blocks`
/** POST …/:id/members */
export const membersUrl = (id: number) => `${groupUrl(id)}/members`

// ─── Replies ───

/**
 * A fixture group as the page holds it: each member's full_name from the
 * users fixture, open, not archived, with no lifecycle reason.
 *
 * @param patch  fields to change, e.g. `{ lifecycle: 'paused' }`.
 */
export function detailOf(id: number, patch: Partial<ChatGroupDetail> = {}): ChatGroupDetail {
  const fixture = CHAT_GROUP_DETAILS.find((g) => g.id === id)
  if (!fixture) throw new Error(`detailOf: no fixture group ${id}`)
  const members = fixture.members.map((m) => ({
    ...m,
    full_name: ADMIN_USERS.find((u) => u.user_id === m.user_id)?.profile?.full_name ?? null,
  }))
  return { ...fixture, members, lifecycle_reason: null, is_archived: false, ...patch }
}

/** The GET …/:id reply for a group, in #111's shape (lifecycle beside `group`). */
export function detailReply(group: ChatGroupDetail): MockReply {
  const { lifecycle, lifecycle_reason, is_archived, ...rest } = group
  return { data: { success: true, group: { ...rest, lifecycle }, lifecycle, lifecycle_reason, is_archived } }
}

/** A refusal reply with a chat-group code, as chatErr sends it. */
export function refusal(status: number, code: string, extra: Record<string, unknown> = {}): MockReply {
  return { status, data: { success: false, error: 'English server text.', code, ...extra } }
}

/**
 * Registers the group's detail, messages (served in one page) and contact
 * blocks.
 *
 * @param options.messages  the messages to serve; the fixture's by default.
 * @returns                 the same mock API, for chaining.
 */
export function serveGroup(
  api: MockApi,
  group: ChatGroupDetail,
  options: { messages?: ChatGroupMessage[] } = {},
): MockApi {
  const messages = options.messages ?? CHAT_GROUP_MESSAGES[group.id] ?? []
  return api
    .on('get', groupUrl(group.id), detailReply(group))
    .on('get', messagesUrl(group.id), messagesAfter(messages))
    .on('get', blocksUrl(group.id), { data: { success: true, items: CHAT_GROUP_CONTACT_BLOCKS[group.id] ?? [] } })
}

/** A messages handler that honours after_id, as the route does. */
export function messagesAfter(messages: ChatGroupMessage[]) {
  return (call: { params?: unknown }): MockReply => {
    const afterId = Number((call.params as { after_id?: number } | undefined)?.after_id ?? 0)
    return { data: { success: true, items: messages.filter((m) => m.id > afterId) } }
  }
}
