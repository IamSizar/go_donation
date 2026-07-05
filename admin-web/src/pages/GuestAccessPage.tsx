// GuestAccessPage — Section 27 "Guest Mode" config (Super-Admin only).
//
// The Primary Administrator toggles which app screens a signed-out guest may
// browse. Each change is PIN-confirmed and saved to the backend; the mobile
// app reads /api/guest/config to decide what to show. Nav-hidden for everyone
// but the super-admin, guarded here, and the backend enforces RequireSuperAdmin.
import { useCallback, useEffect, useState } from 'react'
import { api, describeError, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Resp = { screens: string[]; config: Record<string, boolean> }

// Screen slug → existing nav.* i18n key, so labels stay localized.
const SCREEN_LABEL: Record<string, string> = {
  campaigns: 'nav.campaigns',
  news: 'nav.media',
  city_directory: 'nav.city_guide',
  partners: 'nav.partners',
  marketplace: 'nav.marketplace',
  marriage: 'nav.marriage',
  volunteer: 'nav.volunteers',
}

export default function GuestAccessPage() {
  const { t } = useI18n()
  const { user } = useAuth()
  const toast = useToast()
  const [screens, setScreens] = useState<string[]>([])
  const [config, setConfig] = useState<Record<string, boolean>>({})
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [saving, setSaving] = useState<string | null>(null)

  const amSuper = isSuperAdmin(user)

  const verifyPin = async () => {
    const pin = window.prompt(t('export.pin_prompt'))
    if (pin == null || !pin.trim()) throw new Error(t('export.pin_required'))
    const { data } = await api.post('/api/admin/verify-password', { password: pin })
    if (!data?.ok) throw new Error(data?.error || t('export.pin_incorrect'))
  }

  useEffect(() => {
    if (!amSuper) { setLoading(false); return }
    let cancelled = false
    setLoading(true)
    api
      .get<Resp>('/api/admin/guest_settings')
      .then((res) => {
        if (cancelled) return
        setScreens(res.data.screens ?? [])
        setConfig(res.data.config ?? {})
        setErr(null)
      })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [amSuper])

  const toggle = useCallback(async (screen: string) => {
    const next = !config[screen]
    setSaving(screen)
    try {
      await verifyPin()
      await api.post('/api/admin/guest_settings', { screen, enabled: next })
      setConfig((c) => ({ ...c, [screen]: next }))
      toast.success(t('guest.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(null)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [config, t, toast])

  const screenLabel = (s: string) => (SCREEN_LABEL[s] ? t(SCREEN_LABEL[s]) : s)

  if (!amSuper) {
    return (
      <div className="stack">
        <h1>{t('nav.guest_access')}</h1>
        <div className="error-box">{t('guest.restricted')}</div>
      </div>
    )
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('guest.title')}</h1>
          <p className="muted">{t('guest.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && (
        <div className="card">
          <table className="data-table">
            <thead>
              <tr>
                <th style={{ textAlign: 'start' }}>{t('guest.col_screen')}</th>
                <th style={{ textAlign: 'center', width: '160px' }}>{t('guest.col_visible')}</th>
              </tr>
            </thead>
            <tbody>
              {screens.map((s) => (
                <tr key={s}>
                  <td style={{ textAlign: 'start' }}><strong>{screenLabel(s)}</strong></td>
                  <td style={{ textAlign: 'center' }}>
                    <label className="switch-label" style={{ cursor: 'pointer' }}>
                      <input
                        type="checkbox"
                        checked={!!config[s]}
                        disabled={saving === s}
                        onChange={() => toggle(s)}
                        aria-label={screenLabel(s)}
                      />{' '}
                      <span className="muted">{config[s] ? t('guest.shown') : t('guest.hidden')}</span>
                    </label>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
