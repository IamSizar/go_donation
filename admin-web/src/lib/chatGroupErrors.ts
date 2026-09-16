/**
 * chatGroupErrors.ts — the words an operator reads when a chat-group request
 * is refused.
 *
 * WHAT IT CONTAINS
 * - CHAT_GROUP_ERROR_KEYS: every machine `code` the chat-group routes send,
 *   mapped to its i18n message key.
 * - describeChatGroupError(): the message to show for a failure.
 * - describeConnectRequestError(): the same, for the connect-request routes,
 *   whose "not found" is the one refusal still sent without a code.
 * - chatGroupErrorArea(): where a form should show that message.
 *
 * THE CONTRACT
 * Every chatErr answer on the backend is `{ success: false, error, code }`:
 * not_group_member 403, group_not_found 404, connect_request_decided 409,
 * team_member_role_not_allowed 400,
 * group_member_conflict 409, group_label_conflict 409,
 * guest_member_not_allowed 400, group_label_contact 400,
 * group_invalid_input 400, connect_context_not_found 400, server_error 500 and
 * sensitive_data_required 403. Sending a message can also answer
 * chat_lifecycle_closed 409 (with the staff reason in `lifecycle_reason`) and
 * contact_details_blocked 422. A signed-out or rejected session answers 401
 * unauthorized (#26496), which reuses A15's `error.auth_required` wording. A missing connect request answers 404
 * connect_request_not_found (#26478); an older backend sends the same 404
 * with no code, which describeConnectRequestError still translates.
 *
 * HOW IT EXTENDS describeError
 * lib/api.ts's describeError already resolves `code` through `error.<code>`,
 * passes a 4xx's own text through, and hides a 5xx's prose behind a generic
 * line. This module keeps those rules and adds:
 *   1. a TYPED list of the codes, so a missing translation fails a test
 *      (chatGroupErrors.test.ts) instead of printing English on an Arabic
 *      screen;
 *   2. the staff reason on a lifecycle refusal, in the operator's language;
 *   3. a translated "not found" for connect requests;
 *   4. a last resort that never shows axios's own "Request failed with status
 *      code 400" when a refusal carries no text at all;
 *   5. no developer message on screen when the failure is a bug rather than
 *      a request: it is logged, and the operator gets the generic line.
 */
import axios from 'axios'
import { describeError } from './api'
import { translate } from './i18n'

// ─── The codes ───

/** Every refusal code a chat-group admin route sends. */
export const CHAT_GROUP_ERROR_CODES = [
  'guest_member_not_allowed',
  'team_member_role_not_allowed',
  'connect_context_not_found',
  'group_member_conflict',
  'group_label_conflict',
  'group_label_contact',
  'group_invalid_input',
  'group_not_found',
  'not_group_member',
  'connect_request_decided',
  'connect_request_not_found',
  'sensitive_data_required',
  'server_error',
  'chat_lifecycle_closed',
  'contact_details_blocked',
  'unauthorized',
] as const

/** One chat-group refusal code. */
export type ChatGroupErrorCode = (typeof CHAT_GROUP_ERROR_CODES)[number]

/**
 * code → i18n key. The keys live under `error.*` on purpose: describeError
 * resolves `error.<code>` too, so any screen that shows a chat-group failure
 * through the older helper still gets the translation.
 */
export const CHAT_GROUP_ERROR_KEYS: Record<ChatGroupErrorCode, string> = {
  guest_member_not_allowed: 'error.guest_member_not_allowed',
  // A team group shows real names, so the server takes only volunteer and
  // staff accounts in one (Zaid's decision, 2026-09-16).
  team_member_role_not_allowed: 'error.team_member_role_not_allowed',
  connect_context_not_found: 'error.connect_context_not_found',
  group_member_conflict: 'error.group_member_conflict',
  group_label_conflict: 'error.group_label_conflict',
  group_label_contact: 'error.group_label_contact',
  group_invalid_input: 'error.group_invalid_input',
  group_not_found: 'error.group_not_found',
  not_group_member: 'error.not_group_member',
  connect_request_decided: 'error.connect_request_decided',
  connect_request_not_found: 'error.connect_request_not_found',
  sensitive_data_required: 'error.sensitive_data_required',
  // A 500 reads as the dashboard's generic server line, never as the
  // driver's "Database error.".
  server_error: 'error.server',
  chat_lifecycle_closed: 'error.chat_lifecycle_closed',
  contact_details_blocked: 'error.contact_details_blocked',
  // #26496 — the 401 the chat-group routes now code. It is the same situation
  // A15's `error.auth_required` already words ("Your session has ended. Please
  // sign in again."), in all four locales, so it is reused rather than
  // duplicated under a second key.
  unauthorized: 'error.auth_required',
}

/** The message for the uncoded 404 a missing connect request answers. */
export const CONNECT_REQUEST_NOT_FOUND_KEY = 'error.connect_request_not_found'

/** Where a form shows a refusal: beside the member rows, or atop the form. */
export type ChatGroupErrorArea = 'members' | 'form'

/** Refusals about WHO is in the group or what they are called. */
const MEMBER_AREA_CODES: ReadonlySet<ChatGroupErrorCode> = new Set<ChatGroupErrorCode>([
  'guest_member_not_allowed',
  'team_member_role_not_allowed',
  'group_member_conflict',
  'group_label_conflict',
  'group_label_contact',
])

// ─── Reading a failure ───

/** The fields of a refusal body this module reads. */
type RefusalBody = { code?: unknown; lifecycle_reason?: unknown }

/** The body of a failed axios request, or undefined for any other failure. */
function refusalBody(err: unknown): RefusalBody | undefined {
  if (!axios.isAxiosError(err)) return undefined
  return err.response?.data as RefusalBody | undefined
}

function isChatGroupErrorCode(value: unknown): value is ChatGroupErrorCode {
  return typeof value === 'string' && (CHAT_GROUP_ERROR_CODES as readonly string[]).includes(value)
}

/**
 * The chat-group refusal code a failed request carries.
 *
 * @param err  anything a rejected call threw.
 * @returns    the code, or null for any other failure (no response, no code,
 *             or a code this module does not know).
 */
export function chatGroupErrorCode(err: unknown): ChatGroupErrorCode | null {
  const code = refusalBody(err)?.code
  return isChatGroupErrorCode(code) ? code : null
}

/**
 * The lifecycle refusal, followed by the reason staff gave when they paused or
 * ended the group. The server's own sentence already carries that reason, but
 * in English, so it is re-attached here in the operator's language.
 */
function lifecycleMessage(err: unknown): string {
  const message = translate(CHAT_GROUP_ERROR_KEYS.chat_lifecycle_closed)
  const reason = refusalBody(err)?.lifecycle_reason
  if (typeof reason !== 'string' || reason.trim() === '') return message
  return `${message} ${translate('chat_lifecycle.reason_shown', { reason: reason.trim() })}`
}

/**
 * A failure that is not a request at all: a bug in the caller, such as the
 * guard buildCreateGroupBody throws on a draft that skipped validation. Its
 * message is written for a developer and in English, so it goes to the
 * console for them, and the operator gets the generic line.
 */
function describeUnexpectedFailure(err: unknown): string {
  console.error('chat groups: unexpected failure', err)
  return translate('error.unknown')
}

/**
 * The message to show the operator for a failed chat-group request, in their
 * language.
 *
 * Order: a failure that is not a request (logged, generic line) → a known
 * code's translation (with the staff reason for a lifecycle refusal) →
 * describeError's rules (the "delete cancelled" line, a 4xx's own text, the
 * generic server line for a 5xx, the offline line) → the generic "Something
 * went wrong" when a refusal carried no text at all.
 *
 * @param err  anything a rejected call threw.
 * @returns    a sentence that is safe to put on screen.
 */
export function describeChatGroupError(err: unknown): string {
  if (!axios.isAxiosError(err) && !axios.isCancel(err)) return describeUnexpectedFailure(err)
  const code = chatGroupErrorCode(err)
  if (code === 'chat_lifecycle_closed') return lifecycleMessage(err)
  if (code) return translate(CHAT_GROUP_ERROR_KEYS[code])
  const described = describeError(err)
  // describeError's own last resort is axios's English message, which says
  // nothing an operator can act on.
  if (axios.isAxiosError(err) && err.response && described === err.message) {
    return translate('error.unknown')
  }
  return described
}

/**
 * describeChatGroupError for the connect-request routes (Phase 6c). A missing
 * request answers a plain 404 with no code, which would otherwise reach the
 * operator as the server's English "Connect request not found.".
 *
 * @param err  anything a rejected connect-request call threw.
 * @returns    a sentence that is safe to put on screen.
 */
export function describeConnectRequestError(err: unknown): string {
  const isUncodedNotFound =
    axios.isAxiosError(err) && err.response?.status === 404 && chatGroupErrorCode(err) === null
  return isUncodedNotFound ? translate(CONNECT_REQUEST_NOT_FOUND_KEY) : describeChatGroupError(err)
}

/**
 * Where a form should show this failure.
 *
 * @returns 'members' for refusals about the members or their labels, so the
 *          message sits beside the rows it is about; 'form' otherwise.
 */
export function chatGroupErrorArea(err: unknown): ChatGroupErrorArea {
  const code = chatGroupErrorCode(err)
  return code && MEMBER_AREA_CODES.has(code) ? 'members' : 'form'
}
