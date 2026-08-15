import axios, { AxiosError } from 'axios'
import { translate } from './i18n'

const TOKEN_KEY = 'humanitarian.admin.token'
const USER_KEY = 'humanitarian.admin.user'

export type StoredUser = {
  user_id: number
  phone: string
  role_id: number | null
  is_admin: number  // 1 = admin, 0 = not
  // Phase 6 dashboard access tier: super_admin | admin | supervisor | employee | user
  staff_tier?: string
}

// canExportData gates the CSV / DB-export tools to admin-level staff only
// (Phase 7 · G-07 / M-60). Legacy is_admin=1 accounts are grandfathered in.
export function canExportData(user: StoredUser | null): boolean {
  if (!user) return false
  if (user.staff_tier === 'super_admin' || user.staff_tier === 'admin') return true
  return user.is_admin === 1
}

// isSuperAdmin gates the most sensitive tools (raw DB export, permissions
// management) to the root Super-Admin tier (Phase 7 · M-60).
export function isSuperAdmin(user: StoredUser | null): boolean {
  return !!user && user.staff_tier === 'super_admin'
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token)
  else localStorage.removeItem(TOKEN_KEY)
}

export function getStoredUser(): StoredUser | null {
  const raw = localStorage.getItem(USER_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw) as StoredUser
  } catch {
    return null
  }
}

export function setStoredUser(user: StoredUser | null) {
  if (user) localStorage.setItem(USER_KEY, JSON.stringify(user))
  else localStorage.removeItem(USER_KEY)
}

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || '',
  timeout: 15000,
})

// Absolute URL for a backend-served asset. Images live on the API origin, not
// the dashboard origin, so a bare "/path" would 404. Handles absolute URLs and
// leading slashes.
export function assetUrl(path?: string | null): string {
  if (!path) return ''
  const p = String(path)
  if (/^https?:\/\//i.test(p)) return p
  const base = (import.meta.env.VITE_API_BASE_URL || '').replace(/\/+$/, '')
  return `${base}/${p.replace(/^\/+/, '')}`
}

// Attach Bearer token automatically.
api.interceptors.request.use((config) => {
  const token = getToken()
  if (token) {
    config.headers = config.headers ?? {}
    config.headers['Authorization'] = `Bearer ${token}`
  }
  return config
})

// Auto-logout on 401 (except for the login/OTP endpoints themselves).
api.interceptors.response.use(
  (res) => res,
  (err: AxiosError) => {
    if (err.response?.status === 401) {
      const url = err.config?.url ?? ''
      const isAuthEntry =
        url.includes('/api/auth/login') ||
        url.includes('/api/auth/otp/')
      if (!isAuthEntry) {
        setToken(null)
        setStoredUser(null)
        if (window.location.pathname !== '/login') {
          window.location.href = '/login'
        }
      }
    }
    return Promise.reject(err)
  },
)

// describeError — turn an axios failure into a message an Arabic-speaking
// operator can actually read and act on.
//
// This used to `return data.error` verbatim, which is how the backend's raw
// English "Database error." ended up painted across an Arabic-only dashboard:
// a technical string, in the wrong language, telling the admin nothing they
// could do about it. The rules now, in order:
//
//   1. `code` — the stable machine key handlers send alongside the message.
//      Translated via the `error.*` namespace, so the same failure reads
//      correctly in all four locales.
//   2. 5xx without a code — the server broke, and whatever prose it attached
//      is for the log, not the operator. Always the generic translated line.
//   3. 4xx — validation/permission replies that pages already surface as-is
//      (field messages, "not allowed", etc.). Passed through unchanged so
//      this change stays scoped to server faults.
//   4. No response at all — the request never landed: offline, DNS, timeout.
//
// translate() is the hook-free t() from lib/i18n (the same one the export
// builders use), so this stays a plain function and its ~30 call sites keep
// working untouched.
export function describeError(err: unknown): string {
  if (axios.isAxiosError(err)) {
    if (!err.response) return translate('error.network')
    const data = err.response.data as
      | { error?: string; details?: string; code?: string }
      | undefined
    if (data?.code) {
      const key = `error.${data.code}`
      const msg = translate(key)
      // translate() echoes the key back when nothing matches — fall through to
      // the generic line rather than printing "error.some_new_code" on screen.
      if (msg !== key) return msg
    }
    if (err.response.status >= 500) return translate('error.server')
    if (data?.error) return data.error
    if (data?.details) return data.details
    return err.message
  }
  if (err instanceof Error) return err.message
  return translate('error.unknown')
}
