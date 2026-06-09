// LoginPage — admin-only password login.
//
// Phase 19a — the OTP flow lives on the Flutter app only; the admin
// dashboard uses the single-step login at /api/auth/login.
//
// Phase 27.5 — phone input removed. The admin shell is single-tenant
// (one canonical operator account), so requiring the operator to type
// the phone every time was friction. The phone is hardcoded as
// ADMIN_PHONE below; the form only asks for the password.
//
// Only is_admin=1 accounts are permitted; if someone changes
// ADMIN_PHONE to a regular user's number the backend still returns an
// "admin access required" error so the same login can't slip a
// non-admin into the dashboard.

import { useState, type FormEvent } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'

// Canonical admin account. To swap which admin is bound to this login
// form, update this constant — no other code changes needed.
const ADMIN_PHONE = '9647500000099'

export default function LoginPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const { login } = useAuth()
  const { t } = useI18n()

  // DEV CONVENIENCE: the admin password is pre-filled so you don't have to
  // remember it during local development. REMOVE THIS DEFAULT before any
  // production / public deployment — replace with useState('').
  const [password, setPassword] = useState('test123')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  // Bring the admin back to wherever RequireAuth bounced them from, or
  // fall back to the dashboard root.
  const from = (location.state as { from?: { pathname: string } } | null)?.from?.pathname ?? '/'

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      const { data } = await api.post('/api/auth/login', {
        phone: ADMIN_PHONE,
        password,
      })
      const token = data?.access_token as string
      if (!token) throw new Error(t('auth.no_token'))
      const isAdmin = Number(data.account?.is_admin ?? 0)
      if (isAdmin !== 1) {
        setError(t('auth.admin_required'))
        return
      }
      login(token, {
        user_id: data.account?.user_id ?? data.user_id,
        phone: data.account?.phone ?? ADMIN_PHONE,
        role_id: data.account?.role_id ?? data.role_id ?? null,
        is_admin: isAdmin,
      })
      navigate(from, { replace: true })
    } catch (err) {
      setError(describeError(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <img
          src="/et-logo.png"
          alt="ET"
          width={64}
          height={64}
          style={{ borderRadius: 16, marginBottom: 16, boxShadow: '0 8px 24px rgba(27,55,201,0.35)' }}
        />
        <span className="login-eyebrow">{t('auth.eyebrow')}</span>
        <h1>{t('auth.welcome')}</h1>
        <p className="muted">{t('auth.subtitle')}</p>

        {error && <div className="error-box">{error}</div>}

        <form onSubmit={handleSubmit} className="stack">
          <label>
            {t('auth.password')}
            <input
              type="password"
              autoFocus
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              required
              disabled={busy}
              autoComplete="current-password"
            />
          </label>
          <button type="submit" disabled={busy || !password.trim()}>
            {busy ? t('auth.signing_in') : t('auth.sign_in')}
          </button>
        </form>
      </div>
    </div>
  )
}
