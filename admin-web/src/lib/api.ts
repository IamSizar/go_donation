import axios, { AxiosError } from 'axios'
import { translate } from './i18n'

const TOKEN_KEY = 'humanitarian.admin.token'
const USER_KEY = 'humanitarian.admin.user'

export type StoredUser = {
  user_id: number
  phone: string
  role_id: number | null
  // Legacy display flag. A15 — it no longer gates ANYTHING, here or on the
  // server: it had drifted out of sync with staff_tier in both directions.
  // Kept on the type only so sessions stored before that change still parse.
  is_admin: number
  // Phase 6 dashboard access tier: super_admin | admin | supervisor | employee | user
  staff_tier?: string
}

// isDashboardStaff mirrors the server's auth.IsDashboardStaff — the tiers that
// may reach /api/admin/* at all. Client-side this is UX only (the server is the
// control), but it must never be MORE permissive than the gate, or the
// dashboard promises actions the API will refuse.
export function isDashboardStaff(user: StoredUser | null): boolean {
  const tier = user?.staff_tier
  return tier === 'super_admin' || tier === 'admin' || tier === 'supervisor' || tier === 'employee'
}

// canExportData gates the CSV / DB-export tools to admin-level staff only
// (Phase 7 · G-07 · M-60), matching auth.IsAdminLevel on the server.
export function canExportData(user: StoredUser | null): boolean {
  return user?.staff_tier === 'super_admin' || user?.staff_tier === 'admin'
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
      // H20 — a WRONG SECOND FACTOR is a 401 too, and it must not be read as
      // "your session ended". Without this the operator who mistypes the
      // confirmation code is thrown out of the dashboard and back to the login
      // screen, which is both baffling and the exact lockout this feature was
      // told not to create. Matched on the server's stable `code`, so only the
      // confirmation refusals are exempted and a genuinely dead token still
      // signs the operator out.
      const code = (err.response.data as { code?: string } | undefined)?.code ?? ''
      const isSecondFactorRefusal = code.startsWith('main_admin_')
      if (!isAuthEntry && !isSecondFactorRefusal) {
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

// withMainAdminConfirmation — the client half of H20.
//
// A change to the Primary Administrator's own account (their sign-in phone,
// their email, their password, their tier) is refused by the server until it
// carries a code that was delivered to BOTH that account's phone and its email.
// The refusal is a 428 with `code: 'main_admin_confirmation_required'` plus
// masked hints for the two channels it went to.
//
// This wrapper is what turns that into one step for the operator: run the
// request; if the server asks for the code, prompt for it and run the request
// once more with `confirmation_code` merged in. It deliberately retries EXACTLY
// ONCE — a loop here would turn a mistyped code into an interrogation, and the
// server already caps the guesses.
//
// `send` receives the extra body fields to merge, so the caller keeps ownership
// of the URL, the method and the rest of the payload:
//
//	await withMainAdminConfirmation((extra) =>
//	  api.post(`/api/admin/users/${id}/password`, { password, ...extra }))
//
// Every OTHER failure — including the "email is not configured on the server"
// refusal, which is the one production will meet today — is re-thrown untouched
// so the page's normal describeError path shows it. This wrapper never swallows
// a refusal and never retries one it was not asked to.
export async function withMainAdminConfirmation<T>(
  send: (extra: Record<string, unknown>) => Promise<T>,
): Promise<T> {
  try {
    return await send({})
  } catch (e) {
    if (!axios.isAxiosError(e) || !e.response) throw e
    const data = e.response.data as
      | { code?: string; phone_hint?: string; email_hint?: string }
      | undefined
    if (data?.code !== 'main_admin_confirmation_required') throw e

    const code = window.prompt(
      translate('perm.main_admin_confirm_prompt', {
        phone: data.phone_hint ?? '',
        email: data.email_hint ?? '',
      }),
    )
    if (code == null || !code.trim()) {
      throw new Error(translate('perm.main_admin_confirm_required'))
    }
    return await send({ confirmation_code: code.trim() })
  }
}
