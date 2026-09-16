/**
 * chatExport.ts — turns ONE chat conversation into the rows and columns an
 * export writes, for each chat system the dashboard oversees.
 *
 * WHAT IT CONTAINS
 *   - The message shapes the admin messages routes return:
 *       donor ↔ owner and support  GET /api/admin/chats/:id/messages           (messages:view)
 *       marriage                   GET /api/admin/marriage/chats/:id/messages  (marriage:view)
 *       staff ↔ staff              GET /api/admin/staff-chats/:id/messages     (participants only)
 *     Each sends the whole history in one reply, unpaged.
 *   - One row engine (toExportRow), and a builder per chat system that names
 *     each sender's role in the interface language.
 *   - The column lists, the filename stem and the document title.
 *   - The loaders the donor and marriage pages hand to ExportCsvButton. Staff
 *     chat has no loader on purpose; StaffChatPage explains why.
 *
 * HOW IT FITS
 * ExportCsvButton calls a page's loader only after the PIN step-up, then hands
 * the rows and columns to lib/csv.ts. csv.ts translates the headers through
 * fieldLabelFor (col.message_id …) and does all the CSV/Excel/Word/PDF
 * escaping, so nothing here escapes anything. An export reads through the same
 * route, and so the same permission, as the page that shows the conversation.
 *
 * WHAT A ROW NEVER HOLDS
 * Contact details. A row is built field by field, never by spreading the
 * message, so a phone or email a route might add later cannot reach a file.
 *
 * GROUP CHATS (E3, not built yet)
 * The chat-group detail page will add each sender's masked label and role in
 * the group: toExportRow's optional group fields plus groupChatExportColumns().
 */
import { api } from './api'
import type { CsvColumn } from './csv'
import { translate } from './i18n'
import { ROLE_BENEFICIARY, ROLE_DONOR, ROLE_VOLUNTEER } from './userProfileFields'

// ─── Message shapes ───

/** What every admin chat message carries, whichever system it came from. */
export type ExportableMessage = {
  id: number
  sender_user_id: number
  sender_name: string | null
  body: string
  /** RFC 3339, as Go marshals time.Time. */
  created_at: string
}

/** A donor-chat message. sender_role is 0 for support, else the sender's app role_id. */
export type DonorChatMessage = ExportableMessage & { thread_id: number; sender_role: number }

/** A marriage-chat message (marriagechat.RoleRequester / RoleOwner / RoleStaff). */
export type MarriageChatMessage = ExportableMessage & {
  thread_id: number
  sender_role: 'requester' | 'owner' | 'staff'
}

/** A staff-chat message. It has no role; the sender's staff tier stands in for one. */
export type StaffChatMessage = ExportableMessage & { thread_id: number }

/** One participant of a staff chat, with the tier that names their messages. */
export type StaffChatParty = { user_id: number; staff_tier: string | null | undefined }

/** The chat system a conversation belongs to. It names the file and the title. */
export type ChatExportKind = 'donor' | 'support' | 'marriage' | 'staff' | 'group'

/** The two cells only a group export fills. */
export type GroupExportFields = { masked_label?: string; role_in_group?: string }

/** One exported line, one per message. */
export type ChatExportRow = {
  message_id: number
  /** ISO-8601 UTC. */
  sent_at: string
  sender_name: string
  sender_user_id: number
  /** Already translated. */
  sender_role: string
  body: string
} & GroupExportFields

// ─── Role names ───

/** chat.RoleSupport (backend/internal/chat/chat.go): staff replying as support. */
const DONOR_ROLE_SUPPORT = 0

/**
 * What the chat pages call a staff sender. MessagesPage and MarriageChatsPage
 * both label staff messages t('nav.support'), so a file says what the screen says.
 */
const SUPPORT_KEY = 'nav.support'

/**
 * A participant's donor-chat sender_role is their users.role_id at send time
 * (handlers/chat.go PostMessage). The keys are the ones UserPicker and
 * DetailPage already name role ids with.
 */
const APP_ROLE_KEY: Record<number, string> = {
  [ROLE_DONOR]: 'registrations.role_donor',
  [ROLE_BENEFICIARY]: 'registrations.role_beneficiary',
  [ROLE_VOLUNTEER]: 'registrations.role_volunteer',
}

/** Marriage sender roles. Staff is named as the marriage chat page names it. */
const MARRIAGE_ROLE_KEY: Record<string, string> = {
  requester: 'status.requester',
  owner: 'status.owner',
  staff: SUPPORT_KEY,
}

/**
 * translate(), with a fallback for a key that has no entry. translate() hands
 * the key itself back in that case, and a raw key must never reach a file.
 */
function labelOr(key: string, fallback: () => string): string {
  const label = translate(key)
  return label === key ? fallback() : label
}

/** "Role 9": a role no mapping knows, labelled rather than printed bare. */
function unknownRole(role: string | number): string {
  return translate('export.role_unknown', { role })
}

/** The readable name of a donor-chat sender_role. */
export function donorRoleLabel(role: number): string {
  const key = role === DONOR_ROLE_SUPPORT ? SUPPORT_KEY : APP_ROLE_KEY[role]
  return key ? labelOr(key, () => unknownRole(role)) : unknownRole(role)
}

/** The readable name of a marriage-chat sender_role. */
export function marriageRoleLabel(role: string): string {
  const key = MARRIAGE_ROLE_KEY[role]
  return key ? labelOr(key, () => unknownRole(role)) : unknownRole(role)
}

/** A staff tier's label (status.super_admin …), or "Staff" when the tier is unknown. */
export function staffTierLabel(tier: string | null | undefined): string {
  const staff = () => translate('status.staff')
  return tier ? labelOr(`status.${tier}`, staff) : staff()
}

// ─── Rows ───

/**
 * A send time as ISO-8601 UTC. Go sends RFC 3339 with an offset and up to
 * nanoseconds; Date keeps milliseconds, which is as fine as a spreadsheet
 * shows. A value that doesn't parse is kept as it arrived, because
 * toISOString() throws on an invalid Date and one odd cell beats no file.
 */
export function toIsoTimestamp(value: string): string {
  const time = Date.parse(value)
  return Number.isNaN(time) ? value : new Date(time).toISOString()
}

/**
 * The row engine every chat system goes through.
 *
 * @param message     the message as the route sent it.
 * @param senderRole  the sender's role, already translated.
 * @param group       masked_label / role_in_group, for a group export only.
 * @returns           one export row; group cells are present only when given.
 */
export function toExportRow(
  message: ExportableMessage,
  senderRole: string,
  group?: GroupExportFields,
): ChatExportRow {
  const row: ChatExportRow = {
    message_id: message.id,
    sent_at: toIsoTimestamp(message.created_at),
    sender_name: message.sender_name?.trim() ?? '',
    sender_user_id: message.sender_user_id,
    sender_role: senderRole,
    body: message.body,
  }
  if (group?.masked_label !== undefined) row.masked_label = group.masked_label
  if (group?.role_in_group !== undefined) row.role_in_group = group.role_in_group
  return row
}

/** Export rows for a donor ↔ owner or support conversation. */
export function donorExportRows(messages: DonorChatMessage[]): ChatExportRow[] {
  return messages.map((m) => toExportRow(m, donorRoleLabel(m.sender_role)))
}

/** Export rows for a marriage conversation. */
export function marriageExportRows(messages: MarriageChatMessage[]): ChatExportRow[] {
  return messages.map((m) => toExportRow(m, marriageRoleLabel(m.sender_role)))
}

/**
 * Export rows for a staff conversation.
 *
 * @param parties  the two participants and their tiers; a sender missing from
 *                 the list is named "Staff".
 */
export function staffExportRows(messages: StaffChatMessage[], parties: StaffChatParty[]): ChatExportRow[] {
  const tierOf = new Map(parties.map((p) => [p.user_id, p.staff_tier]))
  return messages.map((m) => toExportRow(m, staffTierLabel(tierOf.get(m.sender_user_id))))
}

// ─── Columns ───

// Raw field names: lib/csv.ts translates them through col.* at download time.
const CONVERSATION_COLUMNS: CsvColumn<ChatExportRow>[] = [
  { header: 'message_id', get: (r) => r.message_id },
  { header: 'sent_at', get: (r) => r.sent_at },
  { header: 'sender_name', get: (r) => r.sender_name },
  { header: 'sender_user_id', get: (r) => r.sender_user_id },
  { header: 'sender_role', get: (r) => r.sender_role },
  { header: 'body', get: (r) => r.body },
]

const GROUP_COLUMNS: CsvColumn<ChatExportRow>[] = [
  { header: 'masked_label', get: (r) => r.masked_label ?? '' },
  { header: 'role_in_group', get: (r) => r.role_in_group ?? '' },
]

/** The six columns of a one-to-one conversation export. A new array on every call. */
export function chatExportColumns(): CsvColumn<ChatExportRow>[] {
  return [...CONVERSATION_COLUMNS]
}

/** The conversation columns plus masked_label and role_in_group, for a group export. */
export function groupChatExportColumns(): CsvColumn<ChatExportRow>[] {
  return [...CONVERSATION_COLUMNS, ...GROUP_COLUMNS]
}

// ─── Filename and title ───

/**
 * The filename stem, e.g. "donor_chat_7". ExportCsvButton appends the date and
 * the extension. Only digits of the id are kept, so the stem is always
 * filename-safe.
 */
export function chatExportFilenameBase(kind: ChatExportKind, threadId: number): string {
  return `${kind}_chat_${String(threadId).replace(/[^0-9]/g, '')}`
}

/** The document title for Word and PDF, e.g. "Marriage chat #51", translated. */
export function chatExportTitle(kind: ChatExportKind, threadId: number): string {
  return translate('export.chat_title', { chat: translate(`export.chat_${kind}`), id: threadId })
}

// ─── Loaders ───

/** Loads a whole donor ↔ owner or support conversation as export rows. */
export async function loadDonorChatExport(threadId: number): Promise<ChatExportRow[]> {
  const res = await api.get<{ items?: DonorChatMessage[] }>(`/api/admin/chats/${threadId}/messages`)
  return donorExportRows(res.data.items ?? [])
}

/** Loads a whole marriage conversation as export rows. */
export async function loadMarriageChatExport(threadId: number): Promise<ChatExportRow[]> {
  const res = await api.get<{ items?: MarriageChatMessage[] }>(`/api/admin/marriage/chats/${threadId}/messages`)
  return marriageExportRows(res.data.items ?? [])
}
