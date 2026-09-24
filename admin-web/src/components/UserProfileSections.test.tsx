// isBlank decides whether a profile field renders as a value or as "—".
//
// Client feedback round 1: user_profiles.profile_picture is NOT NULL and is
// seeded with the literal string '0' (backend/internal/users/registration.go).
// That is a sentinel, not a path. The server now translates it to null at the
// boundary (NULLIF(up.profile_picture, '0')), so this is belt and braces —
// but the dashboard is what the operator sees, and a '0' arriving from any
// older cached response, an export, or a path this fix did not reach still
// became assetUrl('0') → "<API base>/0" and rendered a broken image.
import { describe, expect, it } from 'vitest'

import { isBlank } from './UserProfileSections'

describe('isBlank', () => {
  it('treats the absent values as blank', () => {
    expect(isBlank(null)).toBe(true)
    expect(isBlank(undefined)).toBe(true)
    expect(isBlank('')).toBe(true)
    expect(isBlank('   ')).toBe(true)
  })

  it("treats the '0' profile-picture sentinel as blank", () => {
    // The seed the NOT NULL column carries when nobody has uploaded anything.
    expect(isBlank('0')).toBe(true)
    expect(isBlank(' 0 ')).toBe(true)
  })

  it('keeps real values, including ones that merely contain a zero', () => {
    expect(isBlank('uploads/avatars/real.jpg')).toBe(false)
    expect(isBlank('uploads/0/avatar.jpg')).toBe(false)
    expect(isBlank('00')).toBe(false)
    expect(isBlank('0.0')).toBe(false)
  })

  it('leaves non-string values alone — only the string sentinel is special', () => {
    // A numeric 0 is a legitimate answer for a count field (family size,
    // rooms, floors) and must still render as 0, not as "—".
    expect(isBlank(0)).toBe(false)
    expect(isBlank(false)).toBe(false)
  })
})
