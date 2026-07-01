// PushNotificationsPage — compose UI with recommended templates + 3 targets.
//
// Layout:
//   1. Recommended templates panel (occasion shortcuts, EN/AR toggle)
//   2. Target picker (3 tiles): U1 · ALL · ROL  (direct-token target removed)
//   3. Conditional input below the picker (user picker / role chips / nothing)
//   4. Standard title + body + image-url inputs
//   5. Big primary send button + response panel
//
// Backend contract: the request body sends ONE of:
//   { user_id: 5 }                              — U1
//   { all_users: true }                         — ALL
//   { role_id: 2 }                              — ROL  (1=donor 2=beneficiary 3=volunteer)
// All payloads also carry title, body, and optional image_url.

import { useEffect, useState, type FormEvent } from 'react'
import { api, describeError } from '../lib/api'
import type { PushSendResp, PushStatusResp } from '../lib/api-types'
import UserPicker, { type PickedUser } from '../components/UserPicker'
import { PUSH_TEMPLATES, type TemplateLang } from '../lib/pushTemplates'
import { useI18n } from '../lib/i18n'
import { Sparkles, Check, Bell, Smartphone } from 'lucide-react'

// Delivery channel. 'inapp' writes a row to every user's Alerts tab (works
// without FCM, reaches every account). 'push' fires an OS banner via FCM
// (needs the service-account key + a real device).
type Channel = 'inapp' | 'push'

// Phase 27.10 — the raw "Direct token" target was removed; sending now
// always goes through a registered audience (one user / all / one role).
type TargetKind = 'user' | 'all' | 'role'

// One descriptor per target. The `code` field is the 2–3 letter badge
// rendered inside the tile. Title / description / hint are resolved at
// render time via t('page.push.target_<kind>_title|desc|hint').
type Target = {
  kind: TargetKind
  code: string
}

const TARGETS: Target[] = [
  { kind: 'user', code: 'U1' },
  { kind: 'all',  code: 'ALL' },
  { kind: 'role', code: 'ROL' },
]

// Role ids → labels resolved via t('page.push.role_<id>').
const ROLES = [{ id: 1 }, { id: 2 }, { id: 3 }] as const

export default function PushNotificationsPage() {
  const { t } = useI18n()
  const [fcmEnabled, setFcmEnabled] = useState<boolean | null>(null)
  // Phase 27.4 — active device count surfaced from /api/admin/push/status.
  // null = still loading; -1 = backend couldn't read; ≥0 = live count.
  const [activeDevices, setActiveDevices] = useState<number | null>(null)

  // Default to in-app: it always works (push needs FCM + a real device).
  const [channel, setChannel] = useState<Channel>('inapp')
  const [target, setTarget] = useState<TargetKind>('all')
  // Phase 18e — U1 target now uses a typeahead UserPicker; pickedUser holds
  // the chosen row (user_id + name + phone) so the form can confirm who
  // exactly is about to get the notification before send.
  const [pickedUser, setPickedUser] = useState<PickedUser | null>(null)
  const [roleId, setRoleId] = useState<number>(1)
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [imageUrl, setImageUrl] = useState('')
  // Phase 27.8 — language used when a recommended template is applied.
  // Only affects which language's text drops into Title/Text; the admin
  // can still hand-edit afterward.
  const [templateLang, setTemplateLang] = useState<TemplateLang>('en')
  // Highlights the last-applied template card so the admin sees what they
  // picked. Cleared when they edit the title by hand.
  const [activeTemplate, setActiveTemplate] = useState<string | null>(null)

  function applyTemplate(id: string, lang: TemplateLang) {
    const tpl = PUSH_TEMPLATES.find((t) => t.id === id)
    if (!tpl) return
    setTitle(tpl.title[lang])
    setBody(tpl.body[lang])
    setActiveTemplate(id)
    setError(null)
    setSuccess(null)
  }

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [result, setResult] = useState<PushSendResp | null>(null)

  // Reload status (incl. live device count) on mount AND after each send,
  // since a successful broadcast may auto-deactivate dead tokens. The
  // ref-tick pattern matches what the other admin pages use.
  const [statusTick, setStatusTick] = useState(0)
  useEffect(() => {
    let cancelled = false
    api
      .get<PushStatusResp>('/api/admin/push/status')
      .then((r) => {
        if (cancelled) return
        setFcmEnabled(r.data.fcm_enabled)
        setActiveDevices(typeof r.data.active_devices === 'number' ? r.data.active_devices : null)
      })
      .catch(() => { if (!cancelled) setFcmEnabled(false) })
    return () => { cancelled = true }
  }, [statusTick])

  async function submit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setSuccess(null)
    setResult(null)

    if (!title.trim()) { setError(t('page.push.err_title_required')); return }
    if (!body.trim())  { setError(t('page.push.err_body_required'));  return }

    // ── In-app channel — writes to every user's Alerts tab. Always works,
    //    no FCM needed. Supports "all users" or "by role".
    if (channel === 'inapp') {
      const payload: Record<string, unknown> = { title: title.trim(), body: body.trim() }
      if (target === 'role') {
        if (!roleId || roleId <= 0) { setError(t('page.push.err_pick_role')); return }
        payload.role_id = roleId
      }
      // 'all' → role_id omitted (every active user).
      setBusy(true)
      try {
        const res = await api.post<{ success: boolean; sent: number }>(
          '/api/admin/notifications/broadcast',
          payload,
        )
        setSuccess(
          `Delivered to ${res.data.sent} user${res.data.sent === 1 ? '' : 's'}' in-app Alerts inbox.`,
        )
      } catch (err) {
        setError(describeError(err))
      } finally {
        setBusy(false)
      }
      return
    }

    // ── Push channel — OS banner via FCM (needs key + real device).
    const payload: Record<string, unknown> = { title: title.trim(), body: body.trim() }
    if (imageUrl.trim()) payload.image_url = imageUrl.trim()

    switch (target) {
      case 'user': {
        if (!pickedUser) { setError(t('page.push.err_pick_user')); return }
        payload.user_id = pickedUser.user_id
        break
      }
      case 'all':
        payload.all_users = true
        break
      case 'role':
        if (!roleId || roleId <= 0) { setError(t('page.push.err_pick_role')); return }
        payload.role_id = roleId
        break
    }

    setBusy(true)
    try {
      const res = await api.post<PushSendResp>('/api/admin/push/send', payload)
      setResult(res.data)
      // Phase 27.4 — if the server reached 0 devices, the message above
      // ("0 of 0 delivered") would be misleading. Tell the admin
      // explicitly that no active device matched their target. The
      // server-side error path catches an empty result list and returns
      // a 400 — but if it ever returns 200/0 (e.g. all tokens dead
      // mid-broadcast), we still want a clear message here.
      if (res.data.attempts === 0) {
        setSuccess(null)
        setError(t('page.push.err_no_devices'))
      } else {
        setSuccess(t('page.push.sent_ok', { sent: res.data.sent, attempts: res.data.attempts }))
      }
      // A successful send may have auto-deactivated dead tokens — refresh
      // the active device counter so the badge reflects reality.
      setStatusTick((t) => t + 1)
    } catch (err) {
      setError(describeError(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('page.push.compose')}</h1>
          <p className="muted">{t('page.push.subtitle')}</p>
        </div>
        <div className="row" style={{ gap: 8 }}>
          {/* Phase 27.4 — surface live device count so the admin can spot
              "all_users → 0 reachable" issues BEFORE clicking Send. */}
          {activeDevices !== null && activeDevices >= 0 && (
            <span
              className={`badge ${activeDevices > 0 ? 'ok' : 'off'}`}
              title={t('page.push.devices_title')}
            >
              {activeDevices} {activeDevices === 1 ? t('page.push.device') : t('page.push.devices')}
            </span>
          )}
          {fcmEnabled !== null && (
            <span className={`badge ${fcmEnabled ? 'ok' : 'off'}`}>
              FCM {fcmEnabled ? t('page.push.fcm_enabled') : t('page.push.fcm_not_configured')}
            </span>
          )}
        </div>
      </div>

      {fcmEnabled === false && (
        <div className="info-box">
          <strong>{t('page.push.fcm_box_title')}</strong>{' '}
          <strong>{t('common.push_inapp_bold')}</strong>{t('common.push_inapp_mid')}
          <code style={{ background: 'transparent', padding: 0 }}>backend/firebase-credentials.json</code>
          {t('common.push_inapp_end')}{t('page.push.fcm_box_post')}
        </div>
      )}

      {/* Phase 27.4 — explicit warning when broadcast / role / user targets
          would reach zero devices. The 'token' target bypasses the table
          so we leave that case alone (it works with the literal string). */}
      {fcmEnabled !== false && activeDevices === 0 && (
        <div className="info-box">
          <strong>{t('page.push.no_devices_title')}</strong>{' '}
          {t('page.push.no_devices_body')}
        </div>
      )}

      {/* Phase 27.8 — recommended templates. One tap fills Title + Text in
          the selected language. Pure front-end convenience; the send path
          is unchanged. */}
      <div className="card stack" style={{ gap: 16 }}>
        <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 10 }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{ fontSize: 15, fontWeight: 800, display: 'flex', alignItems: 'center', gap: 6 }}>
              <Sparkles size={16} strokeWidth={2.4} /> {t('page.push.quick_templates')}
            </span>
            <span className="muted" style={{ fontSize: 12.5 }}>
              {t('page.push.quick_templates_sub')}
            </span>
          </div>
          {/* Segmented EN / AR pill toggle */}
          <div
            role="radiogroup"
            aria-label={t('page.push.template_language')}
            style={{
              display: 'inline-flex',
              padding: 3,
              borderRadius: 999,
              background: 'var(--color-surface-2, rgba(127,127,127,0.10))',
              border: '1px solid var(--color-border, rgba(127,127,127,0.18))',
              gap: 2,
            }}
          >
            {(['en', 'ar'] as const).map((lang) => {
              const on = templateLang === lang
              return (
                <button
                  key={lang}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => {
                    setTemplateLang(lang)
                    // Re-apply the current pick in the new language so the
                    // form updates live without a second card tap.
                    if (activeTemplate) applyTemplate(activeTemplate, lang)
                  }}
                  style={{
                    minWidth: 64,
                    padding: '6px 14px',
                    borderRadius: 999,
                    border: 'none',
                    cursor: 'pointer',
                    fontWeight: 700,
                    fontSize: 13,
                    boxShadow: on ? '0 2px 6px rgba(27,55,201,0.35)' : 'none',
                    background: on ? '#1B37C9' : 'transparent',
                    color: on ? '#fff' : 'var(--color-text-h)',
                    transition: 'background .15s ease, color .15s ease, box-shadow .15s ease',
                  }}
                >
                  {lang === 'en' ? 'EN' : 'عربي'}
                </button>
              )
            })}
          </div>
        </div>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(204px, 1fr))',
            gap: 12,
          }}
        >
          {PUSH_TEMPLATES.map((tpl) => {
            const isActive = activeTemplate === tpl.id
            const Icon = tpl.icon
            return (
              <button
                key={tpl.id}
                type="button"
                onClick={() => applyTemplate(tpl.id, templateLang)}
                title={tpl.title[templateLang]}
                className="tpl-card"
                style={{
                  position: 'relative',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 13,
                  padding: '14px 15px',
                  borderRadius: 18,
                  cursor: 'pointer',
                  textAlign: 'left',
                  // A 2px accent ring when active (via boxShadow inset so it
                  // doesn't shift layout), 1px neutral border otherwise.
                  border: '1px solid var(--color-border, rgba(127,127,127,0.16))',
                  background: isActive
                    ? `color-mix(in srgb, ${tpl.accent} 14%, var(--color-surface))`
                    : 'var(--color-surface)',
                  boxShadow: isActive
                    ? `inset 0 0 0 2px ${tpl.accent}, 0 10px 24px -8px color-mix(in srgb, ${tpl.accent} 55%, transparent)`
                    : '0 1px 2px rgba(0,0,0,0.05)',
                  color: 'inherit',
                  transition:
                    'box-shadow .18s ease, background .18s ease, transform .18s ease',
                }}
              >
                {/* Gradient icon tile — white glyph on the occasion's accent
                    gradient with a soft colored glow. The premium lift. */}
                <span
                  aria-hidden
                  style={{
                    flexShrink: 0,
                    width: 48,
                    height: 48,
                    borderRadius: 14,
                    display: 'grid',
                    placeItems: 'center',
                    background: `linear-gradient(135deg, ${tpl.accent}, color-mix(in srgb, ${tpl.accent} 62%, #000))`,
                    boxShadow: `0 6px 14px -4px color-mix(in srgb, ${tpl.accent} 65%, transparent)`,
                  }}
                >
                  <Icon size={24} strokeWidth={2.3} color="#fff" />
                </span>
                {/* Label + tagline */}
                <span style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                  <span
                    style={{
                      fontSize: 14,
                      fontWeight: 800,
                      lineHeight: 1.15,
                      color: 'var(--color-text-h)',
                      whiteSpace: 'nowrap',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                    }}
                  >
                    {tpl.label}
                  </span>
                  <span
                    className="muted"
                    style={{
                      fontSize: 11.5,
                      fontWeight: 500,
                      lineHeight: 1.25,
                      whiteSpace: 'nowrap',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                    }}
                  >
                    {tpl.tagline}
                  </span>
                </span>
                {/* Active = filled accent check in the corner */}
                {isActive && (
                  <span
                    aria-hidden
                    style={{
                      position: 'absolute',
                      top: 10,
                      insetInlineEnd: 10,
                      width: 20,
                      height: 20,
                      borderRadius: 999,
                      background: tpl.accent,
                      color: '#fff',
                      display: 'grid',
                      placeItems: 'center',
                      boxShadow: `0 2px 6px color-mix(in srgb, ${tpl.accent} 55%, transparent)`,
                    }}
                  >
                    <Check size={13} strokeWidth={3.2} />
                  </span>
                )}
              </button>
            )
          })}
        </div>
        <span className="hint">
          {t('page.push.templates_hint')}
        </span>
      </div>

      <form onSubmit={submit} className="card stack">
        {/* === Delivery channel — In-app (always works) vs Push (needs FCM) === */}
        <div>
          <span className="form-label" style={{ display: 'block', marginBottom: 8 }}>
            Delivery channel
          </span>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            {([
              { kind: 'inapp', Icon: Bell, title: 'In-app (Alerts tab)', desc: 'Shows in every user’s inbox. Always works.' },
              { kind: 'push',  Icon: Smartphone, title: 'Push (OS banner)', desc: 'Lock-screen banner. Needs FCM + a real device.' },
            ] as const).map(({ kind, Icon, title: ttl, desc }) => {
              const selected = channel === kind
              const disabled = kind === 'push' && fcmEnabled === false
              return (
                <button
                  key={kind}
                  type="button"
                  className={`target-tile${selected ? ' is-selected' : ''}`}
                  onClick={() => {
                    setChannel(kind)
                    setError(null); setSuccess(null); setResult(null)
                    // In-app broadcast supports all/role only — drop single-user.
                    if (kind === 'inapp' && target === 'user') setTarget('all')
                  }}
                  disabled={busy || disabled}
                  aria-pressed={selected}
                  style={{ opacity: disabled ? 0.5 : 1 }}
                  title={disabled ? 'FCM not configured on the server' : undefined}
                >
                  <span className="target-code" aria-hidden="true">
                    <Icon size={20} strokeWidth={2.2} />
                  </span>
                  <span className="target-text">
                    <strong>{ttl}</strong>
                    <span className="muted">{desc}</span>
                  </span>
                  {selected && (
                    <svg className="target-check" width="18" height="18" viewBox="0 0 24 24"
                      fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round"
                      strokeLinejoin="round" aria-hidden="true">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  )}
                </button>
              )
            })}
          </div>
        </div>

        {/* === Target picker — single-select === */}
        <div>
          <span className="form-label" style={{ display: 'block', marginBottom: 8 }}>
            {t('page.push.target_label')}
          </span>
          <div
            className="target-grid"
            role="radiogroup"
            aria-label={t('page.push.target_aria')}
          >
            {TARGETS.filter((tg) => !(channel === 'inapp' && tg.kind === 'user')).map((tg) => {
              const selected = target === tg.kind
              return (
                <button
                  key={tg.kind}
                  type="button"
                  className={`target-tile${selected ? ' is-selected' : ''}`}
                  onClick={() => { setTarget(tg.kind); setError(null) }}
                  role="radio"
                  aria-checked={selected}
                  disabled={busy}
                >
                  <span className="target-code" aria-hidden="true">{tg.code}</span>
                  <span className="target-text">
                    <strong>{t(`page.push.target_${tg.kind}_title`)}</strong>
                    <span className="muted">{t(`page.push.target_${tg.kind}_desc`)}</span>
                  </span>
                  {selected && (
                    <svg
                      className="target-check"
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.5"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      aria-hidden="true"
                    >
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  )}
                </button>
              )
            })}
          </div>
        </div>

        {/* === Conditional input for the picked target === */}
        {target === 'user' && (
          <label>
            {t('col.user')}
            {/* Search-as-you-type picker — uses /api/admin/users?q=…
                so the admin doesn't need to know user_ids. When a user is
                picked the search input collapses to a chip showing the
                name + phone + role, so it's unmistakable WHO is about to
                receive the notification. */}
            <UserPicker
              value={pickedUser}
              onChange={setPickedUser}
              disabled={busy}
              placeholder={t('page.push.user_search_placeholder')}
            />
            <span className="hint">{t('page.push.target_user_hint')}</span>
          </label>
        )}

        {target === 'all' && (
          <div className="warn-box">
            <strong>{t('page.push.broadcast_mode')}</strong> {t('page.push.target_all_hint')}
          </div>
        )}

        {target === 'role' && (
          <div>
            <span className="form-label" style={{ display: 'block', marginBottom: 6 }}>
              {t('col.role')}
            </span>
            <div className="role-pills" role="radiogroup" aria-label={t('col.role')}>
              {ROLES.map((r) => (
                <button
                  key={r.id}
                  type="button"
                  className={`role-pill${roleId === r.id ? ' is-selected' : ''}`}
                  onClick={() => setRoleId(r.id)}
                  role="radio"
                  aria-checked={roleId === r.id}
                  disabled={busy}
                >
                  {t(`page.push.role_${r.id}`)}
                </button>
              ))}
            </div>
            <span className="hint" style={{ marginTop: 6, display: 'block' }}>{t('page.push.target_role_hint')}</span>
          </div>
        )}

        {/* === Standard message inputs === */}
        <label>
          {t('col.title')}
          <input
            value={title}
            onChange={(e) => { setTitle(e.target.value); setActiveTemplate(null) }}
            placeholder={t('page.push.title_placeholder')}
            disabled={busy}
            dir="auto"
          />
        </label>

        <label>
          {t('col.body')}
          <input
            value={body}
            onChange={(e) => { setBody(e.target.value); setActiveTemplate(null) }}
            placeholder={t('page.push.body_placeholder')}
            disabled={busy}
            dir="auto"
          />
        </label>

        {channel === 'push' && (
          <label>
            {t('page.push.image_url')} <span className="muted">{t('page.push.optional')}</span>
            <input
              value={imageUrl}
              onChange={(e) => setImageUrl(e.target.value)}
              placeholder="https://yourapp.com/image.png"
              disabled={busy}
            />
          </label>
        )}

        {error && <div className="error-box">{error}</div>}
        {success && (
          <div className="info-box">
            <strong>✓ {success}</strong>
          </div>
        )}

        <div className="row">
          <button
            type="submit"
            disabled={busy || (channel === 'push' && fcmEnabled === false)}
          >
            {busy
              ? t('page.push.sending')
              : channel === 'inapp'
              ? 'Send in-app notification'
              : t('page.push.send')}
          </button>
        </div>

        {/* === Raw FCM response panel === */}
        {result && (
          <pre className="push-response">
{`HTTP ${result.sent > 0 ? 200 : 502}  ·  sent ${result.sent} of ${result.attempts} attempt${result.attempts === 1 ? '' : 's'}

${result.results
  .map((r, i) =>
    r.ok
      ? `[${i + 1}] ✓ OK    token=${r.device_token.slice(0, 24)}…  message=${r.message_name ?? ''}`
      : `[${i + 1}] ✗ FAIL  token=${r.device_token.slice(0, 24)}…  error=${r.error}`,
  )
  .join('\n')}`}
          </pre>
        )}
      </form>
    </div>
  )
}
