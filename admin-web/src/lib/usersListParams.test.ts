import { describe, expect, it } from 'vitest'
import { usersListParams } from './usersListParams'

const base = { page: 1, perPage: 20, q: '', status: '', hideGuests: false, kind: '' as const }

describe('usersListParams', () => {
  it('general list: non-staff only, nothing else narrowed', () => {
    const p = usersListParams(base)
    expect(p.staff).toBe(0)
    expect(p.role_id).toBeUndefined()
    expect(p.guests).toBeUndefined()
    expect(p.hide_guests).toBeUndefined()
  })
  it('donors page (roleId=1) is donors only and never carries guests', () => {
    const p = usersListParams({ ...base, roleId: 1 })
    expect(p).toMatchObject({ staff: 0, role_id: 1, hide_guests: 1 })
    expect(p.guests).toBeUndefined()
  })
  it.each([
    ['beneficiary', 2],
    ['volunteer', 3],
    ['marriage', 5],
  ] as const)('kind %s maps to role %i and excludes guests', (kind, id) => {
    expect(usersListParams({ ...base, kind })).toMatchObject({ staff: 0, role_id: id, hide_guests: 1 })
  })
  it('guests list is guests only: no role, no hide_guests', () => {
    const p = usersListParams({ ...base, kind: 'guest', roleId: 1, hideGuests: true })
    expect(p.guests).toBe(1)
    expect(p.role_id).toBeUndefined()
    expect(p.hide_guests).toBeUndefined()
    expect(p.staff).toBe(0)
  })
  it('the hide-guests toggle still works on the general list', () => {
    expect(usersListParams({ ...base, hideGuests: true }).hide_guests).toBe(1)
  })
})
