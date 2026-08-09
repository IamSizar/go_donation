// ContentPage — generic editor for an app_content CMS page (#9/#35). Loads
// GET /api/content/:slug and saves via PUT /api/admin/content/:slug. Super-Admin
// only (backend enforces RequireSuperAdmin). Reused by Terms, About, Contact.
import { useEffect, useState } from 'react'
import { isAxiosError } from 'axios'
import { api, describeError, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from './PageHead'

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
  // True when the slug is valid but has no row yet — a hint, not an error.
  const [notYetCreated, setNotYetCreated] = useState(false)

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
        setNotYetCreated(false)
      })
      .catch((e) => {
        if (cancelled) return
        // A 404 means this page has no row yet, not that anything is broken —
        // the admin PUT upserts, so saving the empty form below creates it.
        // Showing the red error box here made a brand-new page look like a
        // failure (which is exactly how humanitarian-work presented before it
        // was seeded in migration 096).
        if (isAxiosError(e) && e.response?.status === 404) {
          setForm(empty)
          setErr(null)
          setNotYetCreated(true)
          return
        }
        setErr(describeError(e))
      })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [amSuper, slug])

  const set = (key: keyof Content) => (v: string) => setForm((f) => ({ ...f, [key]: v }))

  const save = async () => {
    setSaving(true)
    try {
      await api.put(`/api/admin/content/${slug}`, form)
      setNotYetCreated(false)
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
      <PageHead>
        <div>
          <h1>{t(titleKey)}</h1>
          <p className="muted">{t(subtitleKey)}</p>
        </div>
        <button className="btn primary" onClick={save} disabled={loading || saving}>
          {saving ? t('common.saving') : t('common.save')}
        </button>
      </PageHead>

      {err && <div className="error-box">{err}</div>}
      {!err && notYetCreated && !loading && (
        <div className="warn-box">
          <strong>{t('content.not_created_title')}</strong> {t('content.not_created_hint')}
        </div>
      )}
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
