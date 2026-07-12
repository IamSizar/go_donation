// IdleLock — §24 sensitive-section auto-lock.
//
// Wraps a sensitive section (Permissions Management) and, after `timeoutMs` of
// no user activity, blanks it behind a lock overlay that requires the admin to
// re-enter their password (verified server-side via /admin/verify-password)
// before continuing. Default two minutes; override with
// VITE_PERMISSIONS_LOCK_SECONDS. Purely additive — it never changes what the
// wrapped section renders, only overlays it when idle.
import { useCallback, useEffect, useRef, useState, type ReactNode, type FormEvent } from 'react'
import { api } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

const DEFAULT_SECONDS = 120

function lockSeconds(): number {
  const v = Number(import.meta.env.VITE_PERMISSIONS_LOCK_SECONDS)
  return Number.isFinite(v) && v > 0 ? v : DEFAULT_SECONDS
}

export default function IdleLock({ children }: { children: ReactNode }) {
  const { t } = useI18n()
  const toast = useToast()
  const [locked, setLocked] = useState(false)
  const [pw, setPw] = useState('')
  const [busy, setBusy] = useState(false)
  const timer = useRef<number | undefined>(undefined)

  const arm = useCallback(() => {
    window.clearTimeout(timer.current)
    timer.current = window.setTimeout(() => setLocked(true), lockSeconds() * 1000)
  }, [])

  useEffect(() => {
    if (locked) {
      window.clearTimeout(timer.current)
      return
    }
    arm()
    const onActivity = () => arm()
    const evs: (keyof WindowEventMap)[] = ['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart']
    for (const e of evs) window.addEventListener(e, onActivity, { passive: true })
    return () => {
      window.clearTimeout(timer.current)
      for (const e of evs) window.removeEventListener(e, onActivity)
    }
  }, [locked, arm])

  const unlock = async (e: FormEvent) => {
    e.preventDefault()
    if (!pw.trim() || busy) return
    setBusy(true)
    try {
      const { data } = await api.post('/api/admin/verify-password', { password: pw })
      if (!data?.ok) {
        toast.error(data?.error || t('lock.wrong'))
        return
      }
      setPw('')
      setLocked(false)
    } catch {
      toast.error(t('lock.wrong'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div style={{ position: 'relative' }}>
      {children}
      {locked && (
        <div className="idle-lock-overlay" role="dialog" aria-modal="true" aria-label={t('lock.title')}>
          <form onSubmit={unlock} className="idle-lock-card stack">
            <h2>{t('lock.title')}</h2>
            <p className="muted">{t('lock.body')}</p>
            <input
              type="password"
              value={pw}
              onChange={(e) => setPw(e.target.value)}
              placeholder="••••••••"
              autoFocus
              disabled={busy}
              autoComplete="current-password"
            />
            <button type="submit" disabled={busy || !pw.trim()}>
              {busy ? t('lock.unlocking') : t('lock.unlock')}
            </button>
          </form>
        </div>
      )}
    </div>
  )
}
