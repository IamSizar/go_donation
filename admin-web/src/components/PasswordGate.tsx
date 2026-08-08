import { useState, type FormEvent, type ReactNode } from 'react'
import { api } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

// A section that asks for the admin's own password before it will render.
//
// Used for System Settings: reaching it already requires being the Primary
// Administrator (navLayout marks /settings superAdminOnly, and the backend
// pins the write routes to RequireSuperAdmin), so this is a second factor
// against an unattended session rather than an access-control boundary —
// same idea as IdleLock and the export PIN, and it verifies against the same
// /admin/verify-password endpoint.
//
// Unlocked state is deliberately per-mount: navigating away and back asks
// again. It is NOT stored in localStorage, which would defeat the point.
export default function PasswordGate({
  children,
  title,
  body,
}: {
  children: ReactNode
  title?: string
  body?: string
}) {
  const { t } = useI18n()
  const toast = useToast()
  const [unlocked, setUnlocked] = useState(false)
  const [pw, setPw] = useState('')
  const [busy, setBusy] = useState(false)

  if (unlocked) return <>{children}</>

  const submit = async (e: FormEvent) => {
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
      setUnlocked(true)
    } catch {
      toast.error(t('lock.wrong'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form onSubmit={submit} className="card stack" style={{ maxWidth: 420 }}>
      <h2 style={{ margin: 0 }}>{title ?? t('gate.title')}</h2>
      <p className="muted" style={{ marginTop: 0 }}>{body ?? t('gate.body')}</p>
      <input
        type="password"
        value={pw}
        onChange={(e) => setPw(e.target.value)}
        placeholder="••••••••"
        autoFocus
        disabled={busy}
        autoComplete="current-password"
      />
      <button className="primary" type="submit" disabled={busy || !pw.trim()}>
        {busy ? t('lock.unlocking') : t('gate.unlock')}
      </button>
    </form>
  )
}
