// ContentPage — generic editor for an app_content CMS page (#9/#35). Loads
// GET /api/content/:slug and saves via PUT /api/admin/content/:slug. Super-Admin
// only (backend enforces RequireSuperAdmin). Reused by Terms, About, Contact.
import { useEffect, useState } from 'react'
import { api, describeError, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Content = {
  slug: string
  title_en: string; title_ar: string; title_ckb: string; title_kmr: string
  body_en: string; body_ar: string; body_ckb: string; body_kmr: string
}

const LANGS: Array<{ suf: 'en' | 'ar' | 'ckb' | 'kmr'; labelKey: string; rtl: boolean }> = [
  { suf: 'en', labelKey: 'common.lang_en', rtl: false },
  { suf: 'ar', labelKey: 'common.lang_ar', rtl: true },
  { suf: 'ckb', labelKey: 'common.lang_sorani', rtl: true },
  { suf: 'kmr', labelKey: 'common.lang_badini', rtl: true },
]

export default function ContentPage({ slug, titleKey, subtitleKey }: { slug: string; titleKey: string; subtitleKey: string }) {
  const { t } = useI18n()
  const { user } = useAuth()
  const toast = useToast()
  const empty: Content = {
    slug,
    title_en: '', title_ar: '', title_ckb: '', title_kmr: '',
    body_en: '', body_ar: '', body_ckb: '', body_kmr: '',
  }
  const [form, setForm] = useState<Content>(empty)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  const amSuper = isSuperAdmin(user)

  useEffect(() => {
    if (!amSuper) { setLoading(false); return }
    let cancelled = false
    setLoading(true)
    api
      .get<{ content: Content }>(`/api/content/${slug}`)
      .then((res) => {
        if (cancelled) return
        setForm({ ...empty, ...res.data.content })
        setErr(null)
      })
      .catch((e) => { if (!cancelled) setErr(describeError(e)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [amSuper, slug])

  const set = (key: keyof Content) => (v: string) => setForm((f) => ({ ...f, [key]: v }))

  const save = async () => {
    setSaving(true)
    try {
      await api.put(`/api/admin/content/${slug}`, form)
      toast.success(t('terms.saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(false)
    }
  }

  if (!amSuper) {
    return (
      <div className="stack">
        <h1>{t(titleKey)}</h1>
        <div className="error-box">{t('guest.restricted')}</div>
      </div>
    )
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t(titleKey)}</h1>
          <p className="muted">{t(subtitleKey)}</p>
        </div>
        <button className="btn primary" onClick={save} disabled={loading || saving}>
          {saving ? t('common.saving') : t('common.save')}
        </button>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && LANGS.map(({ suf, labelKey, rtl }) => (
        <div className="card" key={suf}>
          <h3>{t(labelKey)}</h3>
          <label className="field">
            <span className="muted">{t('terms.field_title')}</span>
            <input
              type="text"
              dir={rtl ? 'rtl' : 'ltr'}
              value={form[`title_${suf}` as keyof Content]}
              onChange={(e) => set(`title_${suf}` as keyof Content)(e.target.value)}
            />
          </label>
          <label className="field">
            <span className="muted">{t('terms.field_body')}</span>
            <textarea
              rows={12}
              dir={rtl ? 'rtl' : 'ltr'}
              value={form[`body_${suf}` as keyof Content]}
              onChange={(e) => set(`body_${suf}` as keyof Content)(e.target.value)}
            />
          </label>
        </div>
      ))}
    </div>
  )
}
