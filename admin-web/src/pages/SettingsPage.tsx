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
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import SidebarLayoutEditor from '../components/SidebarLayoutEditor'

type StaffDirectoryEntry = {
  user_id: number
  full_name: string | null
  phone: string
  staff_tier: string
}

type AssistantStats = {
  total_messages: number
  messages_today: number
  messages_7d: number
  ai_answered: number
  local_fallback: number
  tool_calls_used: number
}

export default function SettingsPage() {
  const { t } = useI18n()
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

  const [staffDirectory, setStaffDirectory] = useState<StaffDirectoryEntry[]>([])
  const [supportUserId, setSupportUserId] = useState('')
  const [savingSupportUser, setSavingSupportUser] = useState(false)

  const [assistantEnabled, setAssistantEnabled] = useState(true)
  const [assistantExtra, setAssistantExtra] = useState('')
  const [savingAssistant, setSavingAssistant] = useState(false)
  const [assistantStats, setAssistantStats] = useState<AssistantStats | null>(null)

  useEffect(() => {
    if (!amSuper) { setLoading(false); return }
    let cancelled = false
    setLoading(true)
    Promise.all([
      api.get<{ number: string }>('/api/admin/settings/support-whatsapp'),
      api.get<{ number: string }>('/api/admin/settings/fib-number'),
      api.get<{ minutes: number }>('/api/admin/settings/session-timeout'),
      api.get<{ user_id: number }>('/api/admin/settings/support-user-id'),
      api.get<{ items: StaffDirectoryEntry[] }>('/api/admin/staff-directory'),
      api.get<{ enabled: boolean; extra_instructions: string }>('/api/admin/settings/assistant'),
      api.get<AssistantStats>('/api/admin/assistant/stats'),
    ])
      .then(([wa, fibRes, timeout, supportUser, directory, assistant, stats]) => {
        if (cancelled) return
        setWhatsapp(wa.data.number ?? '')
        setFib(fibRes.data.number ?? '')
        setTimeoutMinutes(String(timeout.data.minutes ?? 20))
        setSupportUserId(supportUser.data.user_id ? String(supportUser.data.user_id) : '')
        setStaffDirectory(directory.data.items ?? [])
        setAssistantEnabled(assistant.data.enabled ?? true)
        setAssistantExtra(assistant.data.extra_instructions ?? '')
        setAssistantStats(stats.data)
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

  async function saveSupportUser() {
    setSavingSupportUser(true)
    try {
      await api.put('/api/admin/settings/support-user-id', {
        user_id: supportUserId ? parseInt(supportUserId, 10) : 0,
      })
      toast.success(t('settings.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingSupportUser(false)
    }
  }

  async function saveAssistant() {
    setSavingAssistant(true)
    try {
      await api.put('/api/admin/settings/assistant', {
        enabled: assistantEnabled,
        extra_instructions: assistantExtra,
      })
      toast.success(t('settings.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingAssistant(false)
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
              <h3 style={{ margin: 0 }}>{t('settings.support_user_title')}</h3>
              <p className="muted" style={{ marginTop: 4 }}>{t('settings.support_user_desc')}</p>
            </div>
            <label className="field" style={{ maxWidth: 320 }}>
              <span className="muted">{t('settings.support_user_label')}</span>
              <select
                value={supportUserId}
                onChange={(e) => setSupportUserId(e.target.value)}
                disabled={savingSupportUser}
              >
                <option value="">{t('settings.support_user_none')}</option>
                {staffDirectory.map((s) => (
                  <option key={s.user_id} value={s.user_id}>
                    {s.full_name || s.phone} ({s.staff_tier})
                  </option>
                ))}
              </select>
            </label>
            <div className="row">
              <button onClick={saveSupportUser} disabled={savingSupportUser}>
                {savingSupportUser ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>

          <div className="card stack" style={{ gap: 12 }}>
            <div>
              <h3 style={{ margin: 0 }}>{t('settings.assistant_title')}</h3>
              <p className="muted" style={{ marginTop: 4 }}>{t('settings.assistant_desc')}</p>
            </div>
            <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <input
                type="checkbox"
                checked={assistantEnabled}
                onChange={(e) => setAssistantEnabled(e.target.checked)}
                disabled={savingAssistant}
              />
              <span className="muted">{t('settings.assistant_enabled_label')}</span>
            </label>
            <label className="field">
              <span className="muted">{t('settings.assistant_extra_label')}</span>
              <textarea
                rows={4}
                value={assistantExtra}
                onChange={(e) => setAssistantExtra(e.target.value)}
                disabled={savingAssistant}
                placeholder={t('settings.assistant_extra_placeholder')}
              />
            </label>
            <div className="row">
              <button onClick={saveAssistant} disabled={savingAssistant}>
                {savingAssistant ? t('common.saving') : t('common.save')}
              </button>
            </div>
            {assistantStats && (
              <div className="stack" style={{ gap: 4, marginTop: 4 }}>
                <span className="muted" style={{ fontSize: 13, fontWeight: 600 }}>
                  {t('settings.assistant_stats_title')}
                </span>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16 }}>
                  <StatItem label={t('settings.assistant_stats_total')} value={assistantStats.total_messages} />
                  <StatItem label={t('settings.assistant_stats_today')} value={assistantStats.messages_today} />
                  <StatItem label={t('settings.assistant_stats_7d')} value={assistantStats.messages_7d} />
                  <StatItem label={t('settings.assistant_stats_ai')} value={assistantStats.ai_answered} />
                  <StatItem label={t('settings.assistant_stats_local')} value={assistantStats.local_fallback} />
                  <StatItem label={t('settings.assistant_stats_tools')} value={assistantStats.tool_calls_used} />
                </div>
              </div>
            )}
          </div>

          <SidebarLayoutEditor />
        </>
      )}
    </div>
  )
}

function StatItem({ label, value }: { label: string; value: number }) {
  return (
    <div style={{ minWidth: 90 }}>
      <div style={{ fontSize: 20, fontWeight: 800 }}>{value}</div>
      <div className="muted" style={{ fontSize: 12 }}>{label}</div>
    </div>
  )
}
