/**
 * chatGroupDetail.ts — the rules behind the chat-group detail page (Phase 6b,
 * OPOS #26399), kept out of the components so they can be tested alone.
 *
 * WHAT IT CONTAINS
 *   - The roster split: active members, and members removed earlier.
 *   - The add-member form: its draft, its validation and its request body.
 *     The rules are 6a's create-dialog rules (lib/chatGroupForm.ts) for ONE
 *     member, checked against the members the group already has.
 *   - The group export (E3, OPOS #26397): one row per message, built field by
 *     field through chatExport.toExportRow, with each sender's role, masked
 *     label and role in the group.
 *
 * HOW IT FITS
 * AddMemberForm uses the form rules, GroupRoster the split, and GroupHeader
 * hands loadGroupChatExport to ExportCsvButton, which calls it only after the
 * PIN step-up. The export reads through the same messages route as the page,
 * so only a caller who may read the group can export it (D4: a masked group
 * already needs sensitive data to read).
 */
import { fetchAllGroupMessages, type ChatGroupDetail, type ChatGroupKind, type ChatGroupMember, type ChatGroupMemberInput, type ChatGroupMessage } from './chatGroupsApi'
import { toExportRow, type ChatExportRow } from './chatExport'
import {
  MEMBER_LABEL_MAX_LENGTH,
  isChatGroupRole,
  looksLikeContactDetail,
  type ChatGroupRole,
  type MemberPerson,
  type MemberRowIssues,
} from './chatGroupForm'
import { translate } from './i18n'

// ─── Constants ───

/** How often the messages pane asks for new messages: the other chat pages' 3 s. */
export const GROUP_POLL_INTERVAL_MS = 3000

// ─── Roster ───

/** Members still in the group, in the order the server sent them. */
export function activeMembers(members: ChatGroupMember[]): ChatGroupMember[] {
  return members.filter((m) => !m.removed_at)
}

/** Members removed earlier, in the order the server sent them. */
export function removedMembers(members: ChatGroupMember[]): ChatGroupMember[] {
  return members.filter((m) => Boolean(m.removed_at))
}

// ─── Add member ───

/** The add-member form's draft. */
export type AddMemberDraft = {
  user: MemberPerson | null
  role: ChatGroupRole | ''
  /** Masked groups only; blank lets the server number it ("Donor 3"). */
  label: string
}

/** The result of {@link validateAddMember}. */
export type AddMemberValidation = {
  issues: MemberRowIssues
  isValid: boolean
  /** The person was removed earlier, so adding restores their old row (D3). */
  reactivates: boolean
}

/** A fresh, empty draft. */
export function emptyAddMemberDraft(): AddMemberDraft {
  return { user: null, role: '', label: '' }
}

/** The person issue: required, and not someone already active. */
function personIssue(draft: AddMemberDraft, active: ChatGroupMember[]): MemberRowIssues {
  if (!draft.user) return { user: { key: 'chat_groups.form.member_user_required' } }
  const userId = draft.user.user_id
  return active.some((m) => m.user_id === userId) ? { user: { key: 'chat_groups.detail.member_active' } } : {}
}

/**
 * The masked label's issues. Only ACTIVE members' labels count: the server
 * frees a removed member's label (a reactivation that finds it taken is
 * refused there with group_label_conflict).
 */
function labelIssues(label: string, active: ChatGroupMember[]): MemberRowIssues {
  const trimmed = label.trim()
  if (trimmed === '') return {}
  const issues: MemberRowIssues = {}
  const folded = trimmed.toLocaleLowerCase()
  if (trimmed.length > MEMBER_LABEL_MAX_LENGTH) {
    issues.label = { key: 'chat_groups.form.label_too_long', vars: { max: MEMBER_LABEL_MAX_LENGTH } }
  } else if (active.some((m) => m.masked_label.trim().toLocaleLowerCase() === folded)) {
    issues.label = { key: 'chat_groups.form.label_duplicate' }
  }
  // A hint, never a block: the server's group_label_contact is the control.
  if (looksLikeContactDetail(trimmed)) issues.labelHint = { key: 'chat_groups.form.label_contact_hint' }
  return issues
}

/**
 * Checks an add-member draft against the group it would join.
 *
 * @param draft  the form's values.
 * @param group  the group's kind (labels are checked for masked only) and roster.
 * @returns      the issues (i18n keys), whether nothing blocks the submit, and
 *               whether the person would be reactivated.
 */
export function validateAddMember(
  draft: AddMemberDraft,
  group: Pick<ChatGroupDetail, 'kind' | 'members'>,
): AddMemberValidation {
  const active = activeMembers(group.members)
  const issues: MemberRowIssues = {
    ...personIssue(draft, active),
    ...(isChatGroupRole(draft.role) ? {} : { role: { key: 'chat_groups.form.member_role_required' } }),
    ...(group.kind === 'masked' ? labelIssues(draft.label, active) : {}),
  }
  const userId = draft.user?.user_id
  const reactivates = removedMembers(group.members).some((m) => m.user_id === userId)
  return { issues, isValid: !(issues.user || issues.role || issues.label), reactivates }
}

/**
 * The POST …/:id/members body for a valid draft. The route reads `label`
 * (adminGroupMemberReq in handlers/chat_group_admin.go); a team group sends ''.
 *
 * @throws Error when the draft has no person or role — a caller bug, since the
 *         form only submits a draft validateAddMember passed.
 */
export function buildAddMemberBody(draft: AddMemberDraft, kind: ChatGroupKind): ChatGroupMemberInput {
  if (!draft.user || !draft.role) throw new Error('buildAddMemberBody: the draft is incomplete; validate it first')
  return { user_id: draft.user.user_id, role_in_group: draft.role, label: kind === 'masked' ? draft.label.trim() : '' }
}

// ─── Export ───

/** A role in the group, translated; the raw value when no label exists. */
function roleLabel(role: string): string {
  const key = `status.${role}`
  const label = translate(key)
  return label === key ? role : label
}

/**
 * Export rows for a group conversation. A member's message carries their
 * role, masked label (masked groups) and role_in_group; a staff message
 * (sender_member_id 0, or a member no longer in the roster) is named "Staff"
 * with both group cells blank, so every row has the same columns.
 */
export function groupExportRows(messages: ChatGroupMessage[], members: ChatGroupMember[]): ChatExportRow[] {
  const byId = new Map(members.map((m) => [m.id, m]))
  return messages.map((message) => {
    const member = message.sender_member_id ? byId.get(message.sender_member_id) : undefined
    if (!member) return toExportRow(message, translate('status.staff'), { masked_label: '', role_in_group: '' })
    return toExportRow(message, roleLabel(member.role_in_group), {
      masked_label: member.masked ? member.masked_label : '',
      role_in_group: member.role_in_group,
    })
  })
}

/**
 * Loads a group's whole history as export rows.
 *
 * @throws the axios error of the first page that fails.
 */
export async function loadGroupChatExport(group: Pick<ChatGroupDetail, 'id' | 'members'>): Promise<ChatExportRow[]> {
  return groupExportRows(await fetchAllGroupMessages(group.id), group.members)
}
