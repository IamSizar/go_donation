/**
 * chatGroupForm.ts — the rules a new chat group must pass, as pure functions.
 *
 * WHAT IT CONTAINS
 * - The draft the create dialog edits (GroupDraft, MemberDraft).
 * - validateGroupDraft(): every broken rule, as i18n keys, per field.
 * - visibleIssues(): only the issues on fields the operator has touched.
 * - buildCreateGroupBody(): the exact POST /api/admin/chat-groups body.
 * - looksLikeContactDetail(): the heuristic behind the label hint.
 *
 * HOW IT FITS
 * CreateGroupDialog and MemberRowsEditor render what these return. Nothing
 * here touches React, the network or the translations, so every rule is
 * tested directly in chatGroupForm.test.ts. The server still checks all of
 * it again: these rules exist so a doomed request is never sent.
 *
 * THE RULES, AND WHY
 * - A kind is required: the server refuses a group without one.
 * - A team title is required (decision D7) and at most 200 characters, the
 *   limit agreed for member_title.
 * - At least one member, each with a person, and no person twice: the
 *   database has UNIQUE(group_id, user_id), which today answers a bare 500.
 * - A role from donor, beneficiary, volunteer or staff: the vocabulary the
 *   backend numbers labels by (chatgroups.go autoLabelName) and staff join as.
 * - Masked labels are trimmed and at most 100 characters. A blank label is
 *   allowed; the server fills in "Donor 1". Two labels may not match ignoring
 *   case, because the database has a case-insensitive unique index on active
 *   masked labels (migration 120).
 * - A label that looks like a phone number or email address gets a HINT, not
 *   a block. The server refuses the exact shapes moderation.ScanContact
 *   finds (Iraqi mobile numbers, ordinary addresses); this heuristic is
 *   deliberately broader, so blocking on it would refuse labels the server
 *   would accept.
 */
import type { ChatGroupKind, CreateGroupBody } from './chatGroupsApi'

// ─── Vocabulary and limits ───

/** The roles a member can hold in a group. */
export const CHAT_GROUP_ROLES = ['donor', 'beneficiary', 'volunteer', 'staff'] as const

/** One member role. */
export type ChatGroupRole = (typeof CHAT_GROUP_ROLES)[number]

/** The longest team title, in characters, after trimming. */
export const TEAM_TITLE_MAX_LENGTH = 200

/** The longest masked label, in characters, after trimming. */
export const MEMBER_LABEL_MAX_LENGTH = 100

/** Digits in one run, joined by separators, that read as a phone number. */
const PHONE_MIN_DIGITS = 7

/** Separators allowed between two digits of one number ("0770 - 123"). */
const MAX_JOINER_RUN = 3

/** An ordinary email address: the pattern moderation.ScanContact uses. */
const EMAIL_PATTERN = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/

/** Characters that may sit inside a number: spaces, dashes, dots, brackets, bidi marks. */
const JOINER_PATTERN = /[\s\-.,/\\()_*+،‐‑–—\p{Cf}]/u

// ─── Draft types ───

/** A person as the member picker hands them over (UserPicker's PickedUser). */
export type MemberPerson = {
  user_id: number
  phone: string
  role_id: number | null
  full_name: string | null
}

/** One member row being edited. `key` is stable for the row's lifetime. */
export type MemberDraft = {
  key: string
  user: MemberPerson | null
  role: ChatGroupRole | ''
  label: string
}

/** The whole create-group form. */
export type GroupDraft = {
  kind: ChatGroupKind | null
  title: string
  members: MemberDraft[]
}

/** A message to show: an i18n key and the values it interpolates. */
export type FieldMessage = { key: string; vars?: Record<string, number> }

/** What is wrong on one member row. `labelHint` never blocks the submit. */
export type MemberRowIssues = {
  user?: FieldMessage
  role?: FieldMessage
  label?: FieldMessage
  labelHint?: FieldMessage
}

/** Everything wrong with a draft, keyed by field; `rows` by member key. */
export type GroupFormIssues = {
  kind?: FieldMessage
  title?: FieldMessage
  members?: FieldMessage
  rows: Record<string, MemberRowIssues>
}

/** The outcome of {@link validateGroupDraft}. */
export type GroupFormValidation = { issues: GroupFormIssues; isValid: boolean }

/** The member-row fields a touch can be recorded for. */
export type MemberField = 'user' | 'role' | 'label'

// ─── Drafts ───

/** A member row with nothing filled in. */
export function emptyMemberDraft(key: string): MemberDraft {
  return { key, user: null, role: '', label: '' }
}

/** A fresh form: no kind yet, no title, one empty member row. */
export function emptyGroupDraft(): GroupDraft {
  return { kind: null, title: '', members: [emptyMemberDraft('m1')] }
}

/**
 * The key for a new member row: one past the highest `m<n>` on screen, so a
 * key is never shared by two rows that exist at the same time.
 */
export function nextMemberKey(rows: MemberDraft[]): string {
  const highest = rows.reduce((max, row) => Math.max(max, Number(row.key.slice(1)) || 0), 0)
  return `m${highest + 1}`
}

/** The id a touch on one member field is recorded under. */
export function memberFieldId(rowKey: string, field: MemberField): string {
  return `${rowKey}.${field}`
}

/** Whether a value is one of the four member roles. */
export function isChatGroupRole(value: string): value is ChatGroupRole {
  return (CHAT_GROUP_ROLES as readonly string[]).includes(value)
}

// ─── Contact-detail heuristic ───

/** A digit's ASCII value across Latin, Arabic-Indic and extended Arabic-Indic. */
function asciiDigit(char: string): string | null {
  const code = char.codePointAt(0) ?? 0
  if (code >= 0x30 && code <= 0x39) return char
  if (code >= 0x660 && code <= 0x669) return String(code - 0x660)
  if (code >= 0x6f0 && code <= 0x6f9) return String(code - 0x6f0)
  return null
}

/** The most digits found in one run, allowing short separator gaps. */
function longestDigitRun(text: string): number {
  let longest = 0
  let run = 0
  let gap = 0
  for (const char of text) {
    if (asciiDigit(char) !== null) {
      run += 1
      gap = 0
      longest = Math.max(longest, run)
    } else if (run > 0 && gap < MAX_JOINER_RUN && JOINER_PATTERN.test(char)) {
      gap += 1
    } else {
      run = 0
      gap = 0
    }
  }
  return longest
}

/**
 * Whether text looks like it carries a phone number or an email address.
 *
 * @returns true for an address, or for seven or more digits in one run (any
 *          digit script, spaces and dashes allowed between them).
 */
export function looksLikeContactDetail(text: string): boolean {
  return EMAIL_PATTERN.test(text) || longestDigitRun(text) >= PHONE_MIN_DIGITS
}

// ─── Validation ───

/** The team title's issue, if any. */
function teamTitleIssue(title: string): FieldMessage | undefined {
  const trimmed = title.trim()
  if (trimmed === '') return { key: 'chat_groups.form.title_required' }
  if (trimmed.length > TEAM_TITLE_MAX_LENGTH) {
    return { key: 'chat_groups.form.title_too_long', vars: { max: TEAM_TITLE_MAX_LENGTH } }
  }
  return undefined
}

/** A row's person issue; records the person in `seen` when there is none. */
function personIssue(member: MemberDraft, seen: Set<number>): MemberRowIssues {
  if (!member.user) return { user: { key: 'chat_groups.form.member_user_required' } }
  if (seen.has(member.user.user_id)) return { user: { key: 'chat_groups.form.member_duplicate' } }
  seen.add(member.user.user_id)
  return {}
}

/** A row's role issue. */
function roleIssue(member: MemberDraft): MemberRowIssues {
  return isChatGroupRole(member.role) ? {} : { role: { key: 'chat_groups.form.member_role_required' } }
}

/** A masked row's label issue and hint; records the label in `seen`. */
function labelIssues(member: MemberDraft, seen: Set<string>): MemberRowIssues {
  const label = member.label.trim()
  if (label === '') return {}
  const issues: MemberRowIssues = {}
  const folded = label.toLocaleLowerCase()
  if (label.length > MEMBER_LABEL_MAX_LENGTH) {
    issues.label = { key: 'chat_groups.form.label_too_long', vars: { max: MEMBER_LABEL_MAX_LENGTH } }
  } else if (seen.has(folded)) {
    issues.label = { key: 'chat_groups.form.label_duplicate' }
  }
  seen.add(folded)
  if (looksLikeContactDetail(label)) issues.labelHint = { key: 'chat_groups.form.label_contact_hint' }
  return issues
}

/** Every member row's issues, keyed by row; rows with none are left out. */
function memberRowIssues(draft: GroupDraft): Record<string, MemberRowIssues> {
  const rows: Record<string, MemberRowIssues> = {}
  const seenPeople = new Set<number>()
  const seenLabels = new Set<string>()
  for (const member of draft.members) {
    const issues: MemberRowIssues = {
      ...personIssue(member, seenPeople),
      ...roleIssue(member),
      ...(draft.kind === 'masked' ? labelIssues(member, seenLabels) : {}),
    }
    if (Object.keys(issues).length > 0) rows[member.key] = issues
  }
  return rows
}

/** Whether any issue blocks the submit. A label hint never does. */
function hasBlockingIssue(issues: GroupFormIssues): boolean {
  if (issues.kind || issues.title || issues.members) return true
  return Object.values(issues.rows).some((row) => Boolean(row.user || row.role || row.label))
}

/**
 * Checks a draft against every rule in this file's header.
 *
 * @returns the issues per field (i18n keys), and whether nothing blocks the
 *          submit.
 */
export function validateGroupDraft(draft: GroupDraft): GroupFormValidation {
  const issues: GroupFormIssues = { rows: memberRowIssues(draft) }
  if (draft.kind === null) issues.kind = { key: 'chat_groups.form.kind_required' }
  const title = draft.kind === 'team' ? teamTitleIssue(draft.title) : undefined
  if (title) issues.title = title
  if (draft.members.length === 0) issues.members = { key: 'chat_groups.form.members_required' }
  return { issues, isValid: !hasBlockingIssue(issues) }
}

/**
 * Only the issues on fields the operator has touched, so an untouched form is
 * not painted red before anyone has typed. The submit button still uses the
 * full validation, so hiding an issue never lets a doomed request through.
 *
 * @param touched  field ids: 'kind', 'title', 'members', and memberFieldId().
 */
export function visibleIssues(issues: GroupFormIssues, touched: ReadonlySet<string>): GroupFormIssues {
  const shown: GroupFormIssues = { rows: {} }
  for (const field of ['kind', 'title', 'members'] as const) {
    if (issues[field] && touched.has(field)) shown[field] = issues[field]
  }
  for (const [rowKey, row] of Object.entries(issues.rows)) {
    const visible: MemberRowIssues = {}
    if (row.user && touched.has(memberFieldId(rowKey, 'user'))) visible.user = row.user
    if (row.role && touched.has(memberFieldId(rowKey, 'role'))) visible.role = row.role
    if (touched.has(memberFieldId(rowKey, 'label'))) Object.assign(visible, { label: row.label, labelHint: row.labelHint })
    if (visible.user || visible.role || visible.label || visible.labelHint) shown.rows[rowKey] = visible
  }
  return shown
}

// ─── The request body ───

/**
 * The POST /api/admin/chat-groups body for a valid draft. A masked group
 * sends member_title ''; a team group sends every label as ''; titles and
 * labels are trimmed.
 *
 * @throws Error when the draft has no kind or a row has no person — a caller
 *         bug, since the dialog only submits a draft validateGroupDraft passed.
 */
export function buildCreateGroupBody(draft: GroupDraft): CreateGroupBody {
  const { kind } = draft
  if (kind === null) throw new Error('buildCreateGroupBody: the draft has no kind; validate it first')
  const members = draft.members.map((member) => {
    if (!member.user) throw new Error(`buildCreateGroupBody: member row ${member.key} has no person`)
    return {
      user_id: member.user.user_id,
      role_in_group: member.role,
      label: kind === 'masked' ? member.label.trim() : '',
    }
  })
  return { kind, member_title: kind === 'team' ? draft.title.trim() : '', members }
}
