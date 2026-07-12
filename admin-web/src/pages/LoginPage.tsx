// LoginPage — admin-only username + password login.
//
// Phase 30 — admins sign in with a username + password via
// POST /api/auth/admin/login. This replaces the old single-tenant
// hardcoded-phone login, so the dashboard now supports any number of
// admin accounts (each a users row with a username, bcrypt password_hash,
// and is_admin=1).
//
// Only is_admin=1 accounts are permitted: the backend rejects non-admins,
// and this form double-checks is_admin in the response before storing the
// session.

import { useState, type FormEvent } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { api, describeError } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'

export default function LoginPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const { login } = useAuth()
  const { t } = useI18n()

  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  // §24 admin-login 2FA (only reached when the server has ADMIN_LOGIN_2FA on).
  // After a correct password the server replies {status:'otp_required'} instead
  // of a token; we then show a code field and re-submit username+password+otp.
  const [otpRequired, setOtpRequired] = useState(false)
  const [otp, setOtp] = useState('')
  const [phoneHint, setPhoneHint] = useState('')

  // Bring the admin back to wherever RequireAuth bounced them from, or
  // fall back to the dashboard root.
  const from = (location.state as { from?: { pathname: string } } | null)?.from?.pathname ?? '/'

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      const { data } = await api.post('/api/auth/admin/login', {
        username: username.trim(),
        password,
        otp: otpRequired ? otp.trim() : undefined,
      })
      // Two-factor challenge: password was accepted, a code was sent. Reveal the
      // OTP field and wait for the second submit.
      if (data?.status === 'otp_required') {
        setOtpRequired(true)
        setPhoneHint(String(data.phone_hint ?? ''))
        if (data.mode === 'demo' && data.demo_code) setOtp(String(data.demo_code))
        return
      }
      const token = data?.access_token as string
      if (!token) throw new Error(t('auth.no_token'))
      const isAdmin = Number(data.account?.is_admin ?? 0)
      if (isAdmin !== 1) {
        setError(t('auth.admin_required'))
        return
      }
      login(token, {
        user_id: data.account?.user_id ?? data.user_id,
        phone: data.account?.phone ?? '',
        role_id: data.account?.role_id ?? data.role_id ?? null,
        is_admin: isAdmin,
        staff_tier: data.account?.staff_tier ?? (isAdmin === 1 ? 'admin' : 'user'),
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
            {t('auth.username')}
            <input
              type="text"
              autoFocus
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="admin"
              required
              disabled={busy}
              autoComplete="username"
            />
          </label>
          <label>
            {t('auth.password')}
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              required
              disabled={busy || otpRequired}
              autoComplete="current-password"
            />
          </label>
          {otpRequired && (
            <label>
              {t('auth.otp_label')}
              <input
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                value={otp}
                onChange={(e) => setOtp(e.target.value)}
                placeholder="123456"
                required
                autoFocus
                disabled={busy}
              />
              <span className="muted" style={{ fontSize: 12 }}>{t('auth.otp_sent', { hint: phoneHint })}</span>
            </label>
          )}
          <button type="submit" disabled={busy || !username.trim() || !password.trim() || (otpRequired && !otp.trim())}>
            {busy ? t('auth.signing_in') : otpRequired ? t('auth.verify') : t('auth.sign_in')}
          </button>
        </form>
      </div>
    </div>
  )
}
