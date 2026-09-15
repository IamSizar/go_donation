/**
 * chatGroupErrors.ts — the words an operator reads when a chat-group request
 * is refused.
 *
 * WHAT IT CONTAINS
 * - CHAT_GROUP_ERROR_KEYS: every machine `code` the chat-group routes send,
 *   mapped to its `error.*` message key in the locale files.
 * - describeChatGroupError(): the message to show for a failure.
 * - chatGroupErrorArea(): where a form should show that message.
 *
 * HOW IT EXTENDS describeError
 * lib/api.ts's describeError already resolves `code` through `error.<code>`,
 * passes a 4xx's own text through, and hides a 5xx's prose behind a generic
 * line. This module keeps those rules and adds two things the chat-group
 * screens need:
 *   1. a TYPED list of the codes, so a missing translation fails a test
 *      (chatGroupErrors.test.ts) instead of printing English on an Arabic
 *      screen;
 *   2. a last resort that never shows axios's own "Request failed with status
 *      code 400" when a refusal carries no text at all.
 *
 * Codes from main today: guest_member_not_allowed, connect_context_not_found.
 * The others come with the backend branches in flight (B1, B3); mapping them
 * now means the dashboard reads correctly the day those land.
 */
import axios from 'axios'
import { describeError } from './api'
import { translate } from './i18n'

// ─── The codes ───

/** Every refusal code a chat-group admin route sends. */
export const CHAT_GROUP_ERROR_CODES = [
  'guest_member_not_allowed',
  'connect_context_not_found',
  'group_member_conflict',
  'group_label_conflict',
  'group_label_contact',
  'group_invalid_input',
  'group_not_found',
  'not_group_member',
  'connect_request_decided',
  'sensitive_data_required',
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
  connect_context_not_found: 'error.connect_context_not_found',
  group_member_conflict: 'error.group_member_conflict',
  group_label_conflict: 'error.group_label_conflict',
  group_label_contact: 'error.group_label_contact',
  group_invalid_input: 'error.group_invalid_input',
  group_not_found: 'error.group_not_found',
  not_group_member: 'error.not_group_member',
  connect_request_decided: 'error.connect_request_decided',
  sensitive_data_required: 'error.sensitive_data_required',
}

/** Where a form shows a refusal: beside the member rows, or atop the form. */
export type ChatGroupErrorArea = 'members' | 'form'

/** Refusals about WHO is in the group or what they are called. */
const MEMBER_AREA_CODES: ReadonlySet<ChatGroupErrorCode> = new Set<ChatGroupErrorCode>([
  'guest_member_not_allowed',
  'group_member_conflict',
  'group_label_conflict',
  'group_label_contact',
])

// ─── Reading a failure ───

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
  if (!axios.isAxiosError(err)) return null
  const code = (err.response?.data as { code?: unknown } | undefined)?.code
  return isChatGroupErrorCode(code) ? code : null
}

/**
 * The message to show the operator for a failed chat-group request, in their
 * language.
 *
 * Order: a known code's translation → describeError's rules (a 4xx's own
 * text, the generic server line for a 5xx, the offline line) → the generic
 * "Something went wrong" when a refusal carried no text at all.
 *
 * @param err  anything a rejected call threw.
 * @returns    a sentence that is safe to put on screen.
 */
export function describeChatGroupError(err: unknown): string {
  const code = chatGroupErrorCode(err)
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
 * Where a form should show this failure.
 *
 * @returns 'members' for refusals about the members or their labels, so the
 *          message sits beside the rows it is about; 'form' otherwise.
 */
export function chatGroupErrorArea(err: unknown): ChatGroupErrorArea {
  const code = chatGroupErrorCode(err)
  return code && MEMBER_AREA_CODES.has(code) ? 'members' : 'form'
}
