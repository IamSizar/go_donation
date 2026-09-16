/**
 * chatGroupForm.test.ts — the rules a new chat group must pass before the
 * Create button lets it reach POST /api/admin/chat-groups.
 *
 * Each rule is pinned against the pure helpers in chatGroupForm.ts, so the
 * dialog tests only have to prove the rules reach the screen, not re-prove
 * every edge. Messages are asserted as i18n KEYS here on purpose: this module
 * never translates, and the dialog tests assert the English words.
 */
import { describe, expect, it } from 'vitest'
import {
  CHAT_GROUP_ROLES,
  MEMBER_LABEL_MAX_LENGTH,
  TEAM_TITLE_MAX_LENGTH,
  buildCreateGroupBody,
  looksLikeContactDetail,
  nextMemberKey,
  validateGroupDraft,
  type GroupDraft,
  type MemberDraft,
  type MemberPerson,
} from './chatGroupForm'

// ─── Builders ───

/** A person as the member picker hands them over. */
function person(userId: number, fullName = `User ${userId}`): MemberPerson {
  return { user_id: userId, phone: `+96477000${userId}`, role_id: 1, full_name: fullName }
}

/** One complete member row; override any field. */
function row(key: string, overrides: Partial<MemberDraft> = {}): MemberDraft {
  return { key, user: person(100 + Number(key.slice(1))), role: 'donor', label: '', ...overrides }
}

/** A complete, valid masked group with two members; override any field. */
function maskedDraft(overrides: Partial<GroupDraft> = {}): GroupDraft {
  return {
    kind: 'masked',
    title: '',
    members: [row('m1', { label: 'Donor A' }), row('m2', { role: 'beneficiary' })],
    ...overrides,
  }
}

/** A complete, valid team group with one member; override any field. */
function teamDraft(overrides: Partial<GroupDraft> = {}): GroupDraft {
  return { kind: 'team', title: 'Distribution volunteers', members: [row('m1', { role: 'volunteer' })], ...overrides }
}

// ─── validateGroupDraft: the group ───

describe('validateGroupDraft — the group itself', () => {
  it('accepts a complete masked group and a complete team group', () => {
    expect(validateGroupDraft(maskedDraft())).toEqual({ issues: { rows: {} }, isValid: true })
    expect(validateGroupDraft(teamDraft())).toEqual({ issues: { rows: {} }, isValid: true })
  })

  it('requires a group kind', () => {
    const result = validateGroupDraft(maskedDraft({ kind: null }))

    expect(result.issues.kind).toEqual({ key: 'chat_groups.form.kind_required' })
    expect(result.isValid).toBe(false)
  })

  it('requires a team title, and whitespace alone is not a title', () => {
    const result = validateGroupDraft(teamDraft({ title: '   ' }))

    expect(result.issues.title).toEqual({ key: 'chat_groups.form.title_required' })
    expect(result.isValid).toBe(false)
  })

  it('accepts a team title of exactly 200 characters and refuses 201', () => {
    const fits = validateGroupDraft(teamDraft({ title: 'a'.repeat(TEAM_TITLE_MAX_LENGTH) }))
    const tooLong = validateGroupDraft(teamDraft({ title: 'a'.repeat(TEAM_TITLE_MAX_LENGTH + 1) }))

    expect(TEAM_TITLE_MAX_LENGTH).toBe(200)
    expect(fits.isValid).toBe(true)
    expect(tooLong.issues.title).toEqual({ key: 'chat_groups.form.title_too_long', vars: { max: 200 } })
    expect(tooLong.isValid).toBe(false)
  })

  it('does not ask a masked group for a title', () => {
    expect(validateGroupDraft(maskedDraft({ title: '' })).issues.title).toBeUndefined()
  })

  it('requires at least one member', () => {
    const result = validateGroupDraft(teamDraft({ members: [] }))

    expect(result.issues.members).toEqual({ key: 'chat_groups.form.members_required' })
    expect(result.isValid).toBe(false)
  })
})

// ─── validateGroupDraft: member rows ───

describe('validateGroupDraft — member rows', () => {
  it('asks for a person on a row that has none', () => {
    const result = validateGroupDraft(teamDraft({ members: [row('m1', { user: null, role: 'volunteer' })] }))

    expect(result.issues.rows.m1.user).toEqual({ key: 'chat_groups.form.member_user_required' })
    expect(result.isValid).toBe(false)
  })

  it('refuses the same person twice and flags only the later row', () => {
    const draft = teamDraft({
      members: [row('m1', { user: person(105) }), row('m2', { user: person(105) })],
    })

    const result = validateGroupDraft(draft)

    expect(result.issues.rows.m1).toBeUndefined()
    expect(result.issues.rows.m2.user).toEqual({ key: 'chat_groups.form.member_duplicate' })
    expect(result.isValid).toBe(false)
  })

  it('requires a role, and only donor, beneficiary, volunteer or staff count as one', () => {
    const blank = validateGroupDraft(teamDraft({ members: [row('m1', { role: '' })] }))
    const unknown = validateGroupDraft(
      teamDraft({ members: [row('m1', { role: 'admin' as MemberDraft['role'] })] }),
    )

    expect(blank.issues.rows.m1.role).toEqual({ key: 'chat_groups.form.member_role_required' })
    expect(unknown.issues.rows.m1.role).toEqual({ key: 'chat_groups.form.member_role_required' })
    expect(unknown.isValid).toBe(false)
  })

  it('accepts each of the four roles', () => {
    expect([...CHAT_GROUP_ROLES]).toEqual(['donor', 'beneficiary', 'volunteer', 'staff'])
    for (const role of CHAT_GROUP_ROLES) {
      expect(validateGroupDraft(teamDraft({ members: [row('m1', { role })] })).isValid).toBe(true)
    }
  })
})

// ─── validateGroupDraft: masked labels ───

describe('validateGroupDraft — masked labels', () => {
  it('allows a blank label, which the server numbers itself', () => {
    const result = validateGroupDraft(maskedDraft({ members: [row('m1', { label: '   ' })] }))

    expect(result.isValid).toBe(true)
  })

  it('measures a label after trimming: 100 characters fit and 101 do not', () => {
    const fits = validateGroupDraft(
      maskedDraft({ members: [row('m1', { label: `  ${'x'.repeat(MEMBER_LABEL_MAX_LENGTH)}  ` })] }),
    )
    const tooLong = validateGroupDraft(
      maskedDraft({ members: [row('m1', { label: 'x'.repeat(MEMBER_LABEL_MAX_LENGTH + 1) })] }),
    )

    expect(MEMBER_LABEL_MAX_LENGTH).toBe(100)
    expect(fits.isValid).toBe(true)
    expect(tooLong.issues.rows.m1.label).toEqual({ key: 'chat_groups.form.label_too_long', vars: { max: 100 } })
    expect(tooLong.isValid).toBe(false)
  })

  it('refuses a label that repeats an earlier one, ignoring case and spaces', () => {
    const draft = maskedDraft({
      members: [row('m1', { label: 'Donor A' }), row('m2', { label: '  donor a ' })],
    })

    const result = validateGroupDraft(draft)

    expect(result.issues.rows.m1).toBeUndefined()
    expect(result.issues.rows.m2.label).toEqual({ key: 'chat_groups.form.label_duplicate' })
    expect(result.isValid).toBe(false)
  })

  it('does not count two blank labels as a repeat', () => {
    const draft = maskedDraft({ members: [row('m1', { label: '' }), row('m2', { label: ' ' })] })

    expect(validateGroupDraft(draft).isValid).toBe(true)
  })

  it('ignores labels on a team group, which never sends them', () => {
    const draft = teamDraft({
      members: [row('m1', { label: 'x'.repeat(300) }), row('m2', { label: 'x'.repeat(300) })],
    })

    expect(validateGroupDraft(draft)).toEqual({ issues: { rows: {} }, isValid: true })
  })

  it('hints, without blocking, when a label looks like a phone number or an email address', () => {
    const draft = maskedDraft({
      members: [row('m1', { label: '0770 123 4567' }), row('m2', { label: 'layla@example.com' })],
    })

    const result = validateGroupDraft(draft)

    expect(result.issues.rows.m1.labelHint).toEqual({ key: 'chat_groups.form.label_contact_hint' })
    expect(result.issues.rows.m2.labelHint).toEqual({ key: 'chat_groups.form.label_contact_hint' })
    expect(result.isValid).toBe(true)
  })
})

// ─── looksLikeContactDetail ───

describe('looksLikeContactDetail', () => {
  it.each([
    ['a national mobile number', '07701234567'],
    ['a number written with spaces', '0770 123 4567'],
    ['an international number', '+964 770 123 4567'],
    ['a number typed with Arabic-Indic digits', '٠٧٧٠١٢٣٤٥٦٧'],
    ['an email address', 'layla@example.com'],
  ])('flags %s', (_name, text) => {
    expect(looksLikeContactDetail(text)).toBe(true)
  })

  it.each([
    ['an ordinary label', 'Donor 1'],
    ['a word', 'Beneficiary'],
    ['a short number', 'Family of 12'],
    ['nothing', ''],
  ])('leaves %s alone', (_name, text) => {
    expect(looksLikeContactDetail(text)).toBe(false)
  })
})

// ─── buildCreateGroupBody ───

describe('buildCreateGroupBody', () => {
  it('sends a masked group with an empty title and trimmed labels', () => {
    const draft = maskedDraft({
      title: 'typed before switching to masked',
      members: [
        row('m1', { user: person(101), role: 'donor', label: '  Donor A ' }),
        row('m2', { user: person(103), role: 'beneficiary', label: '' }),
      ],
    })

    expect(buildCreateGroupBody(draft)).toEqual({
      kind: 'masked',
      member_title: '',
      members: [
        { user_id: 101, role_in_group: 'donor', label: 'Donor A' },
        { user_id: 103, role_in_group: 'beneficiary', label: '' },
      ],
    })
  })

  it('sends a team group with a trimmed title and empty labels', () => {
    const draft = teamDraft({
      title: '  Distribution volunteers  ',
      members: [row('m1', { user: person(105), role: 'volunteer', label: 'typed while masked' })],
    })

    expect(buildCreateGroupBody(draft)).toEqual({
      kind: 'team',
      member_title: 'Distribution volunteers',
      members: [{ user_id: 105, role_in_group: 'volunteer', label: '' }],
    })
  })
})

// ─── nextMemberKey ───

describe('nextMemberKey', () => {
  it('starts at m1 and never reuses a key that is still on screen', () => {
    expect(nextMemberKey([])).toBe('m1')
    expect(nextMemberKey([row('m1'), row('m3')])).toBe('m4')
  })
})
