import { describe, expect, it } from 'vitest'
import { buildEditUserFields, credentialsBody, isProfileFieldShown, splitAccountPatch, USER_FIELDS } from './userEditFields'

describe('splitAccountPatch (#79/#87)', () => {
  it('password-only patch becomes credentials and leaves no profile PATCH', () => {
    const { profilePatch, credentials } = splitAccountPatch({ password: ' secret99 ' })
    expect(profilePatch).toEqual({})
    expect(credentials).toEqual({ password: 'secret99', username: '' })
    expect(credentialsBody(credentials!)).toEqual({ password: 'secret99' })
  })
  it('username travels with the password so a staff account can sign in', () => {
    const { credentials } = splitAccountPatch({ username: ' sup1 ', password: 'secret99', city: 'Erbil' })
    expect(credentialsBody(credentials!)).toEqual({ password: 'secret99', username: 'sup1' })
  })
  it('profile fields stay in the profile PATCH; no credentials when both blank', () => {
    const r = splitAccountPatch({ city: 'Erbil', password: '', username: '' })
    expect(r.profilePatch).toEqual({ city: 'Erbil' })
    expect(r.credentials).toBeNull()
  })
  it('the Edit form offers no password box — an admin cannot set another person\'s password (#87)', () => {
    const keys = USER_FIELDS.map((f) => f.key)
    expect(keys).not.toContain('password')
    expect(keys).not.toContain('username')
  })
})

describe('Edit/New share one visibility rule (#78)', () => {
  const rules = {
    // a donor's form governs national_id; nothing governs tribe_clan for donors
    national_id: { state: 'optional', ruleKey: 'grantor_national_id', governed: true },
  } as const
  const byKey = (k: string) => USER_FIELDS.find((f) => f.key === k)!
  it('donor Edit hides a column the donor form never asks', () => {
    const shown = buildEditUserFields(rules as never, true, 1).map((f) => f.key)
    expect(shown).toContain('national_id')
    expect(shown).not.toContain('tribe_clan')
    expect(shown).toContain('phone')
    expect(shown).not.toContain('password')
  })
  it('a role with no form: Edit shows all, New hides profile boxes', () => {
    expect(isProfileFieldShown(byKey('tribe_clan'), 4, undefined, true)).toBe(true)
    expect(isProfileFieldShown(byKey('tribe_clan'), 4, undefined, false)).toBe(false)
  })
})
