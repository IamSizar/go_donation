/**
 * chatGroupDetail.test.ts — the rules behind the chat-group detail page
 * (Phase 6b, OPOS #26399): the add-member form, the roster split, and the
 * group export rows (E3, OPOS #26397).
 *
 * Arrange → Act → Assert throughout. Labels are asserted as literal English,
 * so a missing translation key cannot pass as its own name.
 */
import { describe, expect, it } from 'vitest'
import {
  activeMembers,
  buildAddMemberBody,
  emptyAddMemberDraft,
  groupExportRows,
  removedMembers,
  validateAddMember,
  type AddMemberDraft,
} from './chatGroupDetail'
import type { ChatGroupMember, ChatGroupMessage } from './chatGroupsApi'

// ─── Fixtures ───

const LAYLA = { user_id: 101, phone: '+9647701002001', role_id: 1, full_name: 'Layla Hassan' }
const NOOR = { user_id: 106, phone: '+9647705556677', role_id: 3, full_name: 'Noor Jabbar' }
const OMAR = { user_id: 104, phone: '+9647701114521', role_id: 1, full_name: 'Omar Khalid' }

const MASKED_MEMBERS: ChatGroupMember[] = [
  { id: 701, user_id: 101, full_name: 'Layla Hassan', role_in_group: 'donor', masked: true, masked_label: 'Donor 1' },
  { id: 702, user_id: 103, full_name: 'Sara Ali', role_in_group: 'beneficiary', masked: true, masked_label: 'Beneficiary' },
  {
    id: 703,
    user_id: 104,
    full_name: 'Omar Khalid',
    role_in_group: 'donor',
    masked: true,
    masked_label: 'Donor 2',
    removed_at: '2026-09-12T16:00:00Z',
  },
]

function draft(patch: Partial<AddMemberDraft>): AddMemberDraft {
  return { ...emptyAddMemberDraft(), ...patch }
}

// ─── Roster ───

describe('activeMembers / removedMembers', () => {
  it('splits the roster on removed_at, keeping the server order', () => {
    expect(activeMembers(MASKED_MEMBERS).map((m) => m.id)).toEqual([701, 702])
    expect(removedMembers(MASKED_MEMBERS).map((m) => m.id)).toEqual([703])
  })
})

// ─── Add member ───

describe('validateAddMember', () => {
  it('blocks an empty draft on the person and the role', () => {
    const result = validateAddMember(emptyAddMemberDraft(), { kind: 'team', members: [] })

    expect(result.isValid).toBe(false)
    expect(result.issues.user?.key).toBe('chat_groups.form.member_user_required')
    expect(result.issues.role?.key).toBe('chat_groups.form.member_role_required')
  })

  it('refuses someone who is already an active member', () => {
    const result = validateAddMember(draft({ user: LAYLA, role: 'donor' }), { kind: 'masked', members: MASKED_MEMBERS })

    expect(result.isValid).toBe(false)
    expect(result.issues.user?.key).toBe('chat_groups.detail.member_active')
  })

  it('lets a removed member be added back, and says their old label returns (D3)', () => {
    const result = validateAddMember(draft({ user: OMAR, role: 'donor' }), { kind: 'masked', members: MASKED_MEMBERS })

    expect(result.isValid).toBe(true)
    expect(result.reactivates).toBe(true)
  })

  it("refuses a masked label another active member already has, ignoring case", () => {
    const result = validateAddMember(draft({ user: NOOR, role: 'volunteer', label: ' donor 1 ' }), {
      kind: 'masked',
      members: MASKED_MEMBERS,
    })

    expect(result.isValid).toBe(false)
    expect(result.issues.label?.key).toBe('chat_groups.form.label_duplicate')
  })

  it('frees the label of a removed member for someone new', () => {
    const result = validateAddMember(draft({ user: NOOR, role: 'volunteer', label: 'Donor 2' }), {
      kind: 'masked',
      members: MASKED_MEMBERS,
    })

    expect(result.isValid).toBe(true)
  })

  it('warns, without blocking, when a label looks like a phone number', () => {
    const result = validateAddMember(draft({ user: NOOR, role: 'volunteer', label: '0770 123 4567' }), {
      kind: 'masked',
      members: MASKED_MEMBERS,
    })

    expect(result.isValid).toBe(true)
    expect(result.issues.labelHint?.key).toBe('chat_groups.form.label_contact_hint')
  })

  it('blocks a label over the length limit', () => {
    const result = validateAddMember(draft({ user: NOOR, role: 'volunteer', label: 'x'.repeat(101) }), {
      kind: 'masked',
      members: MASKED_MEMBERS,
    })

    expect(result.issues.label?.key).toBe('chat_groups.form.label_too_long')
    expect(result.isValid).toBe(false)
  })

  it('ignores the label entirely in a team group', () => {
    const result = validateAddMember(draft({ user: NOOR, role: 'volunteer', label: 'Donor 1' }), {
      kind: 'team',
      members: MASKED_MEMBERS,
    })

    expect(result.isValid).toBe(true)
    expect(result.issues.label).toBeUndefined()
  })
})

describe('buildAddMemberBody', () => {
  it('trims a masked label and sends it as label, the field the route reads', () => {
    expect(buildAddMemberBody(draft({ user: NOOR, role: 'volunteer', label: '  Helper  ' }), 'masked')).toEqual({
      user_id: 106,
      role_in_group: 'volunteer',
      label: 'Helper',
    })
  })

  it('sends a blank label for a team group', () => {
    expect(buildAddMemberBody(draft({ user: NOOR, role: 'volunteer', label: 'x' }), 'team')).toEqual({
      user_id: 106,
      role_in_group: 'volunteer',
      label: '',
    })
  })

  it('throws on a draft that skipped validation', () => {
    expect(() => buildAddMemberBody(emptyAddMemberDraft(), 'team')).toThrow(/validate/)
  })
})

// ─── Export ───

describe('groupExportRows', () => {
  const messages: (ChatGroupMessage & { phone?: string })[] = [
    { id: 1, sender_member_id: 701, sender_user_id: 101, sender_name: 'Layla Hassan', body: 'Hello', created_at: '2026-09-10T09:05:00+03:00' },
    { id: 2, sender_member_id: 0, sender_user_id: 1, sender_name: 'Rana Aziz', body: 'Staff here', created_at: '2026-09-10T09:06:00Z' },
    { id: 3, sender_member_id: 703, sender_user_id: 104, sender_name: 'Omar Khalid', body: 'Hi', created_at: '2026-09-10T09:07:00Z', phone: '+964770' },
  ]

  it('names each member sender with their role, masked label and role_in_group (D4)', () => {
    const [layla, staff, omar] = groupExportRows(messages, MASKED_MEMBERS)

    expect(layla).toEqual({
      message_id: 1,
      sent_at: '2026-09-10T06:05:00.000Z',
      sender_name: 'Layla Hassan',
      sender_user_id: 101,
      sender_role: 'Grantor',
      body: 'Hello',
      masked_label: 'Donor 1',
      role_in_group: 'donor',
    })
    expect(staff).toMatchObject({ sender_name: 'Rana Aziz', sender_role: 'Staff', masked_label: '', role_in_group: '' })
    expect(omar).toMatchObject({ masked_label: 'Donor 2', role_in_group: 'donor' })
  })

  it('never copies a field the row does not name, such as a phone', () => {
    const rows = groupExportRows(messages, MASKED_MEMBERS)

    expect(Object.keys(rows[2]).sort()).toEqual(
      ['body', 'masked_label', 'message_id', 'role_in_group', 'sender_name', 'sender_role', 'sender_user_id', 'sent_at'],
    )
  })

  it('leaves masked_label blank for a team member', () => {
    const team: ChatGroupMember[] = [
      { id: 711, user_id: 105, full_name: 'Yusuf Kareem', role_in_group: 'volunteer', masked: false, masked_label: '' },
    ]
    const [row] = groupExportRows(
      [{ id: 9, sender_member_id: 711, sender_user_id: 105, sender_name: 'Yusuf Kareem', body: 'x', created_at: '2026-09-13T17:00:00Z' }],
      team,
    )

    expect(row).toMatchObject({ sender_role: 'Volunteer', masked_label: '', role_in_group: 'volunteer' })
  })
})
