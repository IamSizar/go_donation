// SettingsPage — "Dashboard Settings" (Note #5). Home for admin-editable
// system-wide settings that don't deserve their own sidebar section. First
// tenant: Session Timeout (the idle-lock duration, previously a hardcoded
// constant in AppShell.tsx). Also picks up the Support WhatsApp number and
// FIB account number — backend endpoints for both already existed
// (#36 / donate-screen convenience alias) but had no admin UI at all until
// now, so they're folded in here rather than getting their own pages too.
//
// Restricted to the Main Admin (Super Admin) — matches the client's explicit
// ask for Session Timeout, and keeps this first version simple rather than
// inventing mixed per-field permission tiers not requested.
import { useEffect, useState } from 'react'
import { api, describeError, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { useToast } from '../lib/toast'
import SidebarLayoutEditor from '../components/SidebarLayoutEditor'

// Note #17 — Marriage subscription package tiers. Must match
// marriageSubscription in backend/internal/handlers/admin_edit.go (the
// single source of truth for valid tier names) and SUBSCRIPTION_STATUSES in
// MarriagePage.tsx.
const MARRIAGE_PACKAGE_TIERS = ['bronze', 'silver', 'gold', 'diamond', 'vip'] as const

export default function SettingsPage() {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const { user } = useAuth()
  const toast = useToast()
  const amSuper = isSuperAdmin(user)

  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)

  const [whatsapp, setWhatsapp] = useState('')
  const [savingWhatsapp, setSavingWhatsapp] = useState(false)

  const [fib, setFib] = useState('')
  const [savingFib, setSavingFib] = useState(false)

  const [timeoutMinutes, setTimeoutMinutes] = useState('20')
  const [savingTimeout, setSavingTimeout] = useState(false)

  // Note #17 — one price-string field per package tier, keyed the same as
  // the backend's {tier: price} map.
  const [prices, setPrices] = useState<Record<string, string>>({})
  const [savingPrices, setSavingPrices] = useState(false)

  useEffect(() => {
    if (!amSuper) { setLoading(false); return }
    let cancelled = false
    setLoading(true)
    Promise.all([
      api.get<{ number: string }>('/api/admin/settings/support-whatsapp'),
      api.get<{ number: string }>('/api/admin/settings/fib-number'),
      api.get<{ minutes: number }>('/api/admin/settings/session-timeout'),
      api.get<{ prices: Record<string, number> }>('/api/admin/settings/marriage-package-prices'),
    ])
      .then(([wa, fibRes, timeout, pricesRes]) => {
        if (cancelled) return
        setWhatsapp(wa.data.number ?? '')
        setFib(fibRes.data.number ?? '')
        setTimeoutMinutes(String(timeout.data.minutes ?? 20))
        const p: Record<string, string> = {}
        for (const tier of MARRIAGE_PACKAGE_TIERS) p[tier] = String(pricesRes.data.prices?.[tier] ?? 0)
        setPrices(p)
        setErr(null)
      })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [amSuper])

  async function saveWhatsapp() {
    setSavingWhatsapp(true)
    try {
      await api.put('/api/admin/settings/support-whatsapp', { number: whatsapp })
      toast.success(t('settings.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingWhatsapp(false)
    }
  }

  async function saveFib() {
    setSavingFib(true)
    try {
      await api.put('/api/admin/settings/fib-number', { number: fib })
      toast.success(t('settings.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingFib(false)
    }
  }

  async function saveTimeout() {
    const n = parseInt(timeoutMinutes, 10)
    if (!Number.isFinite(n) || n < 5 || n > 480) {
      toast.error(t('settings.session_timeout_range'))
      return
    }
    setSavingTimeout(true)
    try {
      await api.put('/api/admin/settings/session-timeout', { minutes: n })
      toast.success(t('settings.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingTimeout(false)
    }
  }

  async function savePrices() {
    const parsed: Record<string, number> = {}
    for (const tier of MARRIAGE_PACKAGE_TIERS) {
      const n = Number(prices[tier])
      if (!Number.isFinite(n) || n < 0) {
        toast.error(t('settings.marriage_prices_invalid', { tier: statusLabel(tier) }))
        return
      }
      parsed[tier] = n
    }
    setSavingPrices(true)
    try {
      await api.put('/api/admin/settings/marriage-package-prices', { prices: parsed })
      toast.success(t('settings.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingPrices(false)
    }
  }

  if (!amSuper) {
    return (
      <div className="stack">
        <h1>{t('settings.title')}</h1>
        <div className="error-box">{t('guest.restricted')}</div>
      </div>
    )
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('settings.title')}</h1>
          <p className="muted">{t('settings.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && (
        <>
          <div className="card stack" style={{ gap: 12 }}>
            <div>
              <h3 style={{ margin: 0 }}>{t('settings.session_timeout_title')}</h3>
              <p className="muted" style={{ marginTop: 4 }}>{t('settings.session_timeout_desc')}</p>
            </div>
            <label className="field" style={{ maxWidth: 260 }}>
              <span className="muted">{t('settings.session_timeout_label')}</span>
              <input
                type="number"
                min={5}
                max={480}
                dir="ltr"
                value={timeoutMinutes}
                onChange={(e) => setTimeoutMinutes(e.target.value)}
                disabled={savingTimeout}
              />
            </label>
            <span className="hint">{t('settings.session_timeout_hint')}</span>
            <div className="row">
              <button onClick={saveTimeout} disabled={savingTimeout}>
                {savingTimeout ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>

          <div className="card stack" style={{ gap: 12 }}>
            <div>
              <h3 style={{ margin: 0 }}>{t('settings.whatsapp_title')}</h3>
              <p className="muted" style={{ marginTop: 4 }}>{t('settings.whatsapp_desc')}</p>
            </div>
            <label className="field" style={{ maxWidth: 320 }}>
              <span className="muted">{t('settings.whatsapp_label')}</span>
              <input
                type="text"
                dir="ltr"
                inputMode="numeric"
                placeholder="9647xxxxxxxxx"
                value={whatsapp}
                onChange={(e) => setWhatsapp(e.target.value)}
                disabled={savingWhatsapp}
              />
            </label>
            <div className="row">
              <button onClick={saveWhatsapp} disabled={savingWhatsapp}>
                {savingWhatsapp ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>

          <div className="card stack" style={{ gap: 12 }}>
            <div>
              <h3 style={{ margin: 0 }}>{t('settings.fib_title')}</h3>
              <p className="muted" style={{ marginTop: 4 }}>{t('settings.fib_desc')}</p>
            </div>
            <label className="field" style={{ maxWidth: 320 }}>
              <span className="muted">{t('settings.fib_label')}</span>
              <input
                type="text"
                dir="ltr"
                value={fib}
                onChange={(e) => setFib(e.target.value)}
                disabled={savingFib}
              />
            </label>
            <div className="row">
              <button onClick={saveFib} disabled={savingFib}>
                {savingFib ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>

          <div className="card stack" style={{ gap: 12 }}>
            <div>
              <h3 style={{ margin: 0 }}>{t('settings.marriage_prices_title')}</h3>
              <p className="muted" style={{ marginTop: 4 }}>{t('settings.marriage_prices_desc')}</p>
            </div>
            <div className="form-grid">
              {MARRIAGE_PACKAGE_TIERS.map((tier) => (
                <label key={tier} className="field" style={{ maxWidth: 220 }}>
                  <span className="muted">{statusLabel(tier)}</span>
                  <input
                    type="number"
                    min={0}
                    dir="ltr"
                    value={prices[tier] ?? ''}
                    onChange={(e) => setPrices((m) => ({ ...m, [tier]: e.target.value }))}
                    disabled={savingPrices}
                  />
                </label>
              ))}
            </div>
            <div className="row">
              <button onClick={savePrices} disabled={savingPrices}>
                {savingPrices ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>

          <SidebarLayoutEditor />
        </>
      )}
    </div>
  )
}
