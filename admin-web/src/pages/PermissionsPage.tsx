// PermissionsPage — Section 24 "Super Admin · Permissions Management".
//
// A role (tier) × module × action matrix the Primary Administrator uses to
// grant/revoke dashboard access. Each toggle is PIN-gated (step-up auth) and
// recorded in the immutable permission_audit_log, shown read-only below the
// matrix. The whole page is super-admin only (nav-hidden + guarded here + the
// backend enforces RequireSuperAdmin).
import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, describeError, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import IdleLock from '../components/IdleLock'
import type { UsersListResp } from '../lib/api-types'

type Matrix = {
  tiers: string[]
  modules: string[]
  actions: string[]
  defaults: Record<string, Record<string, boolean>>
  overrides: { tier: string; module: string; action: string; allowed: boolean }[]
}

type AuditRow = {
  id: number
  actor_name: string | null
  action: string
  target: string | null
  old_value: string | null
  new_value: string | null
  ip_address: string | null
  created_at: string
}

// Module slug → existing nav.* i18n key, so the matrix labels stay localized
// without a second translation set.
const MODULE_LABEL: Record<string, string> = {
  dashboard: 'nav.dashboard', registrations: 'nav.registrations', users: 'nav.users',
  campaigns: 'nav.campaigns', donations: 'nav.donations', sponsorships: 'nav.sponsorships',
  beneficiary: 'nav.beneficiary', marketplace: 'nav.marketplace', in_kind: 'nav.in_kind',
  partners: 'nav.partners', media: 'nav.media', community: 'nav.community',
  city: 'nav.city_guide', marriage: 'nav.marriage', missions: 'nav.missions',
  volunteers: 'nav.volunteers', messages: 'nav.messages', notifications: 'nav.notifications',
  push: 'nav.push', reports: 'nav.reports', audit: 'nav.audit_logs', support: 'nav.support',
  trash: 'nav.trash', sensitive_data: 'perm.sensitive_data',
}

const key = (tier: string, module: string, action: string) => `${tier}|${module}|${action}`

// ── Note 31 — per-employee overrides ────────────────────────────────────
// Every account on the same tier is permission-identical by default; this
// lets a Super-Admin narrow (or widen) ONE specific employee's access
// without touching their whole tier — e.g. an employee assigned solely to
// Volunteers never sees Marriage/Partners/Settings, while other employees
// on the same tier are unaffected.
type StaffOption = { id: number; label: string; tier: string }
type UserCell = { allowed: boolean; source: 'user' | 'tier' }
type UserMatrixResp = {
  user_id: number
  tier: string
  modules: string[]
  actions: string[]
  cells: Record<string, Record<string, UserCell>>
}

function PerEmployeeCard({
  modules, actions, moduleLabel, actionLabel, verifyPin, onChanged,
}: {
  modules: string[]
  actions: string[]
  moduleLabel: (m: string) => string
  actionLabel: (a: string) => string
  verifyPin: () => Promise<void>
  onChanged: () => void
}) {
  const { t } = useI18n()
  const toast = useToast()
  const [staff, setStaff] = useState<StaffOption[]>([])
  const [selected, setSelected] = useState<number | null>(null)
  const [userMatrix, setUserMatrix] = useState<UserMatrixResp | null>(null)
  const [loadingStaff, setLoadingStaff] = useState(true)
  const [loadingMatrix, setLoadingMatrix] = useState(false)
  const [saving, setSaving] = useState<string | null>(null)

  useEffect(() => {
    api
      .get<UsersListResp>('/api/admin/users', { params: { page: 1, per_page: 200 } })
      .then((res) => {
        const opts = (res.data.data ?? [])
          .filter((u) => u.staff_tier && u.staff_tier !== 'user' && u.staff_tier !== 'super_admin')
          .map((u) => ({
            id: u.user_id,
            tier: u.staff_tier!,
            label: `${u.profile?.full_name ?? t('common.user_ref', { id: u.user_id })} — ${u.phone}`,
          }))
        setStaff(opts)
      })
      .catch(() => { /* staff picker is best-effort */ })
      .finally(() => setLoadingStaff(false))
  }, [t])

  const loadUserMatrix = useCallback((userID: number) => {
    setLoadingMatrix(true)
    api
      .get<UserMatrixResp>(`/api/admin/permissions/user/${userID}`)
      .then((res) => setUserMatrix(res.data))
      .catch((e) => toast.error(describeError(e)))
      .finally(() => setLoadingMatrix(false))
  }, [toast])

  useEffect(() => {
    if (selected != null) loadUserMatrix(selected)
    else setUserMatrix(null)
  }, [selected, loadUserMatrix])

  // set: change this employee's override for (module, action). clear: wipe
  // the override so they fall back to their tier's own value.
  const change = async (module: string, action: string, next: boolean | null) => {
    if (selected == null) return
    const k = `${module}|${action}`
    setSaving(k)
    try {
      await verifyPin()
      const { data: otpResp } = await api.post('/api/admin/permissions/otp')
      let promptMsg = t('perm.otp_prompt', { phone: otpResp?.phone_hint ?? '' })
      if (otpResp?.demo_code) {
        promptMsg += `\n\n${t('perm.otp_demo_hint', { code: otpResp.demo_code })}`
      }
      const otp = window.prompt(promptMsg)
      if (otp == null || !otp.trim()) throw new Error(t('perm.otp_required'))
      await api.post(`/api/admin/permissions/user/${selected}`, { module, action, allowed: next, otp: otp.trim() })
      toast.success(t('perm.saved'))
      loadUserMatrix(selected)
      onChanged()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(null)
    }
  }

  return (
    <div className="card" style={{ overflowX: 'auto' }}>
      <h2 style={{ marginTop: 0 }}>{t('perm.per_employee_title')}</h2>
      <p className="muted" style={{ marginTop: 4 }}>{t('perm.per_employee_desc')}</p>

      <label className="field" style={{ maxWidth: 420, marginTop: 12 }}>
        <span className="muted">{t('perm.employee_label')}</span>
        <select
          value={selected ?? ''}
          disabled={loadingStaff}
          onChange={(e) => setSelected(e.target.value ? Number(e.target.value) : null)}
        >
          <option value="">{t('perm.employee_pick')}</option>
          {staff.map((s) => (
            <option key={s.id} value={s.id}>{s.label} ({t(`perm.tier.${s.tier}`)})</option>
          ))}
        </select>
      </label>

      {loadingMatrix && <p className="muted" style={{ marginTop: 12 }}>{t('common.loading')}</p>}

      {userMatrix && !loadingMatrix && (
        <table className="data-table" style={{ marginTop: 12 }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'start' }}>{t('perm.col_module')}</th>
              {actions.map((a) => (
                <th key={a} style={{ textAlign: 'center' }}>{actionLabel(a)}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {modules.map((mod) => (
              <tr key={mod}>
                <td style={{ textAlign: 'start' }}><strong>{moduleLabel(mod)}</strong></td>
                {actions.map((a) => {
                  const cell = userMatrix.cells[mod]?.[a]
                  const k = `${mod}|${a}`
                  const isOverridden = cell?.source === 'user'
                  return (
                    <td key={a} style={{ textAlign: 'center' }}>
                      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                        <input
                          type="checkbox"
                          checked={!!cell?.allowed}
                          disabled={saving === k}
                          onChange={() => change(mod, a, !cell?.allowed)}
                          aria-label={`${moduleLabel(mod)} · ${actionLabel(a)}`}
                          title={isOverridden ? t('perm.overridden_hint') : t('perm.inherited_hint')}
                          style={isOverridden ? { accentColor: 'var(--color-warning, #F59E0B)' } : undefined}
                        />
                        {isOverridden && (
                          <button
                            type="button"
                            className="icon-btn"
                            disabled={saving === k}
                            title={t('perm.reset_to_tier')}
                            onClick={() => change(mod, a, null)}
                          >
                            ↺
                          </button>
                        )}
                      </div>
                    </td>
                  )
                })}
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

export default function PermissionsPage() {
  const { t } = useI18n()
  const { user } = useAuth()
  const toast = useToast()
  const [matrix, setMatrix] = useState<Matrix | null>(null)
  const [state, setState] = useState<Record<string, boolean>>({})
  const [audit, setAudit] = useState<AuditRow[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [saving, setSaving] = useState<string | null>(null)

  const amSuper = isSuperAdmin(user)

  // PIN step-up — required before every permission change (Section 24 2FA:
  // the PIN factor; the OTP factor is a separate follow-up).
  const verifyPin = async () => {
    const pin = window.prompt(t('export.pin_prompt'))
    if (pin == null || !pin.trim()) throw new Error(t('export.pin_required'))
    const { data } = await api.post('/api/admin/verify-password', { password: pin })
    if (!data?.ok) throw new Error(data?.error || t('export.pin_incorrect'))
  }

  const loadAudit = useCallback(async () => {
    try {
      const res = await api.get<{ items: AuditRow[] }>('/api/admin/permissions/audit')
      setAudit(res.data.items ?? [])
    } catch { /* audit is best-effort in the UI */ }
  }, [])

  useEffect(() => {
    if (!amSuper) { setLoading(false); return }
    let cancelled = false
    setLoading(true)
    api
      .get<Matrix>('/api/admin/permissions')
      .then((res) => {
        if (cancelled) return
        const m = res.data
        setMatrix(m)
        // Seed effective state from defaults, then apply stored overrides.
        const eff: Record<string, boolean> = {}
        for (const tier of m.tiers) {
          for (const mod of m.modules) {
            for (const act of m.actions) {
              eff[key(tier, mod, act)] = m.defaults[tier]?.[act] ?? false
            }
          }
        }
        for (const o of m.overrides) eff[key(o.tier, o.module, o.action)] = o.allowed
        setState(eff)
        setErr(null)
      })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    void loadAudit()
    return () => { cancelled = true }
  }, [amSuper, loadAudit])

  const toggle = async (tier: string, module: string, action: string) => {
    const k = key(tier, module, action)
    const next = !state[k]
    setSaving(k)
    try {
      // Two-factor: 1) PIN step-up, then 2) a phone OTP sent to the Super
      // Admin. Both must pass before the change is applied (Section 24).
      await verifyPin()
      const { data: otpResp } = await api.post('/api/admin/permissions/otp')
      let promptMsg = t('perm.otp_prompt', { phone: otpResp?.phone_hint ?? '' })
      if (otpResp?.demo_code) {
        promptMsg += `\n\n${t('perm.otp_demo_hint', { code: otpResp.demo_code })}`
      }
      const otp = window.prompt(promptMsg)
      if (otp == null || !otp.trim()) throw new Error(t('perm.otp_required'))
      await api.post('/api/admin/permissions', { tier, module, action, allowed: next, otp: otp.trim() })
      setState((s) => ({ ...s, [k]: next }))
      toast.success(t('perm.saved'))
      void loadAudit()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(null)
    }
  }

  const tierLabel = (tier: string) => t(`perm.tier.${tier}`)
  const actionLabel = (action: string) => t(`perm.action.${action}`)
  const moduleLabel = (module: string) => (MODULE_LABEL[module] ? t(MODULE_LABEL[module]) : module)
  const auditActionLabel = (a: string) => (a === 'permission_set' ? t('perm.audit_set') : a)

  const auditRows = useMemo(() => audit, [audit])

  if (!amSuper) {
    return (
      <div className="stack">
        <h1>{t('nav.permissions')}</h1>
        <div className="error-box">{t('perm.restricted')}</div>
      </div>
    )
  }

  return (
    <IdleLock>
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('perm.title')}</h1>
          <p className="muted">{t('perm.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {matrix && !loading && matrix.tiers.map((tier) => (
        <div key={tier} className="card" style={{ overflowX: 'auto' }}>
          <h2 style={{ marginTop: 0 }}>{tierLabel(tier)}</h2>
          <table className="data-table">
            <thead>
              <tr>
                <th style={{ textAlign: 'start' }}>{t('perm.col_module')}</th>
                {matrix.actions.map((a) => (
                  <th key={a} style={{ textAlign: 'center' }}>{actionLabel(a)}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {matrix.modules.map((mod) => (
                <tr key={mod}>
                  <td style={{ textAlign: 'start' }}><strong>{moduleLabel(mod)}</strong></td>
                  {matrix.actions.map((a) => {
                    const k = key(tier, mod, a)
                    return (
                      <td key={a} style={{ textAlign: 'center' }}>
                        <input
                          type="checkbox"
                          checked={!!state[k]}
                          disabled={saving === k}
                          onChange={() => toggle(tier, mod, a)}
                          aria-label={`${tierLabel(tier)} · ${moduleLabel(mod)} · ${actionLabel(a)}`}
                        />
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}

      {matrix && !loading && (
        <PerEmployeeCard
          modules={matrix.modules}
          actions={matrix.actions}
          moduleLabel={moduleLabel}
          actionLabel={actionLabel}
          verifyPin={verifyPin}
          onChanged={loadAudit}
        />
      )}

      {/* Read-only, immutable permission audit log. */}
      <div className="card">
        <h2 style={{ marginTop: 0 }}>{t('perm.audit_title')}</h2>
        <table className="data-table">
          <thead>
            <tr>
              <th style={{ textAlign: 'start' }}>{t('perm.col_time')}</th>
              <th style={{ textAlign: 'start' }}>{t('perm.col_actor')}</th>
              <th style={{ textAlign: 'start' }}>{t('perm.col_action')}</th>
              <th style={{ textAlign: 'start' }}>{t('perm.col_target')}</th>
              <th style={{ textAlign: 'start' }}>{t('perm.col_change')}</th>
              <th style={{ textAlign: 'start' }}>{t('perm.col_ip')}</th>
            </tr>
          </thead>
          <tbody>
            {auditRows.length === 0 && (
              <tr><td colSpan={6} className="cell-muted">{t('perm.audit_empty')}</td></tr>
            )}
            {auditRows.map((r) => (
              <tr key={r.id}>
                <td className="muted" style={{ whiteSpace: 'nowrap' }}>{r.created_at?.slice(0, 16).replace('T', ' ')}</td>
                <td>{r.actor_name ?? '—'}</td>
                <td>{auditActionLabel(r.action)}</td>
                <td><code style={{ background: 'transparent', padding: 0 }}>{r.target ?? '—'}</code></td>
                <td className="muted">{r.old_value ?? '—'} → {r.new_value ?? '—'}</td>
                <td className="muted">{r.ip_address ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
    </IdleLock>
  )
}
