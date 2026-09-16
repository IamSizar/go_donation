/**
 * connectRequestForm.ts — the rules behind the connect-request inbox's
 * Approve and Decline dialogs, as pure functions (Phase 6c, OPOS #26400).
 *
 * WHAT IT CONTAINS
 * - CONNECT_REQUEST_FILTERS: the statuses the inbox filters by.
 * - validateDeclineReason(): what is wrong with a decline reason, if anything.
 * - approveDraftFor(): the approve dialog's starting draft, requester first.
 * - requesterIssue(): the one approve rule 6a's create form does not have.
 *
 * THE RULES, AND WHY
 * - A decline reason is required after trimming: the handler answers 400 "A
 *   decline reason is required." for a blank one, and the store trims it.
 * - A decline reason is at most DECLINE_REASON_MAX_LENGTH characters. The
 *   backend has NO length check (decline_reason is TEXT, migration 120); the
 *   limit is the dashboard's own, so the member reads a note, not an essay.
 * - The requester must stay a member: ApproveConnectRequest answers 400
 *   group_invalid_input when they are not in `members`.
 * Every other approve rule (kind, team title D7, people, roles, labels) is
 * 6a's validateGroupDraft, reused as it is.
 */
import type { ConnectRequest, ConnectRequestStatus } from './chatGroupsApi'
import type { FieldMessage, GroupDraft } from './chatGroupForm'

/** The inbox's filters, in the order they are shown; pending is the default. */
export const CONNECT_REQUEST_FILTERS: readonly ConnectRequestStatus[] = ['pending', 'approved', 'declined']

/** Badge tone per status: waiting reads as a warning, decided as settled. */
export const STATUS_TONE: Record<ConnectRequestStatus, string> = {
  pending: 'tone-warning',
  approved: 'tone-success',
  declined: 'tone-danger',
}

/**
 * The requester as the inbox names them: requester_name when the server sent
 * it (D6), otherwise the translated "Requester #id".
 *
 * @param t  the i18n translate function.
 */
export function requesterDisplayName(
  request: Pick<ConnectRequest, 'requester_user_id' | 'requester_name'>,
  t: (key: string, vars?: Record<string, string | number>) => string,
): string {
  const name = request.requester_name?.trim()
  return name || t('chat_groups.inbox.requester_fallback', { id: request.requester_user_id })
}

/** The longest decline reason, in characters, after trimming (dashboard limit). */
export const DECLINE_REASON_MAX_LENGTH = 1000

/**
 * Checks a decline reason as the operator typed it.
 *
 * @returns the broken rule as an i18n key, or undefined when it may be sent.
 */
export function validateDeclineReason(reason: string): FieldMessage | undefined {
  const trimmed = reason.trim()
  if (trimmed === '') return { key: 'chat_groups.inbox.decline.reason_required' }
  if (trimmed.length > DECLINE_REASON_MAX_LENGTH) {
    return { key: 'chat_groups.inbox.decline.reason_too_long', vars: { max: DECLINE_REASON_MAX_LENGTH } }
  }
  return undefined
}

/**
 * The approve dialog's first draft: no kind yet, and the requester already in
 * member row 1. Only the id and (when sent) the name are known, so the phone
 * is '' and the app role null; the picker's chip shows "#id" either way.
 */
export function approveDraftFor(request: ConnectRequest): GroupDraft {
  const person = {
    user_id: request.requester_user_id,
    phone: '',
    role_id: null,
    full_name: request.requester_name ?? null,
  }
  return { kind: null, title: '', members: [{ key: 'm1', user: person, role: '', label: '' }] }
}

/**
 * Whether the draft still includes the requester.
 *
 * @returns the rule as an i18n key when no member row holds them.
 */
export function requesterIssue(draft: GroupDraft, requesterUserId: number): FieldMessage | undefined {
  const included = draft.members.some((member) => member.user?.user_id === requesterUserId)
  return included ? undefined : { key: 'chat_groups.inbox.approve.requester_required' }
}
