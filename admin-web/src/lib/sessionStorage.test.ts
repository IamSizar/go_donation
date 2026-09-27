import { describe, expect, it } from 'vitest'
import { getStoredUser, getToken, setStoredUser, setToken } from './api'

// Owner note: closing the tab or the browser ends the dashboard session. The
// browser drops sessionStorage with the tab and keeps localStorage forever, so
// the login must live in the first and never in the second.
describe('the dashboard login lives only as long as the tab', () => {
  const user = { user_id: 1, phone: '+964', role_id: null, is_admin: 1, staff_tier: 'super_admin' }

  it('keeps the token and user in sessionStorage, not localStorage', () => {
    setToken('abc.def')
    setStoredUser(user)
    expect(sessionStorage.getItem('humanitarian.admin.token')).toBe('abc.def')
    expect(sessionStorage.getItem('humanitarian.admin.user')).toContain('super_admin')
    expect(localStorage.getItem('humanitarian.admin.token')).toBeNull()
    expect(localStorage.getItem('humanitarian.admin.user')).toBeNull()
    expect(getToken()).toBe('abc.def')
    expect(getStoredUser()?.staff_tier).toBe('super_admin')
  })

  it('clears both on sign-out', () => {
    setToken('abc.def')
    setStoredUser(user)
    setToken(null)
    setStoredUser(null)
    expect(getToken()).toBeNull()
    expect(getStoredUser()).toBeNull()
  })

  it('drops a session an older version left in localStorage when the app loads', async () => {
    localStorage.setItem('humanitarian.admin.token', 'old')
    localStorage.setItem('humanitarian.admin.user', '{"user_id":9}')
    // A fresh evaluation of the module, as a page load would do.
    const { vi } = await import('vitest')
    vi.resetModules()
    await import('./api')
    expect(localStorage.getItem('humanitarian.admin.token')).toBeNull()
    expect(localStorage.getItem('humanitarian.admin.user')).toBeNull()
  })

  it('is signed out when sessionStorage is empty, as in a new tab', () => {
    expect(getToken()).toBeNull()
    expect(getStoredUser()).toBeNull()
  })
})
