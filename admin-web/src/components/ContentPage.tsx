// ContentPage — generic editor for an app_content CMS page (#9/#35). Loads
// GET /api/content/:slug and saves via PUT /api/admin/content/:slug. Super-Admin
// only (backend enforces RequireSuperAdmin). Reused by Terms, About, Contact.
//
// K12 — the page also edits its named, ordered SUB-SECTIONS (migration 111),
// saved to PUT /api/admin/content/:slug/sections by the same Save button.
//
// The two halves are exclusive by design, and this is the rule to keep in mind
// when changing this file: when a page has sub-sections, the backend COMPOSES
// `body_*` out of them, so a plain Body textarea shown next to them would be
// silently overwritten on every save. It is therefore rendered only while the
// sub-section list is empty — a page with no sub-sections is a plain blob page,
// exactly as before K12.
//
// K13 — a page passed `contact` also edits its own CONTACT DETAILS (migration
// 112): logo, phone, WhatsApp, email, social links and a localized address.
// They are validated inline before the Save button will fire, mirroring the
// server's ValidateContact.
import { useCallback, useEffect, useState } from 'react'
import { isAxiosError } from 'axios'
import { api, describeError, isSuperAdmin } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import { useRegisterSaveAction } from '../lib/saveAction'
import { validateContactFields } from '../lib/contactFields'
import PageHead from './PageHead'
import ContentSectionsEditor, { type ContentSection } from './ContentSectionsEditor'
import ContentContactEditor, { type ContactValues } from './ContentContactEditor'

type Content = {
  slug: string
  title_en: string; title_ar: string; title_ckb: string; title_kmr: string
  body_en: string; body_ar: string; body_ckb: string; body_kmr: string
} & ContactValues

const LANGS: Array<{ suf: 'en' | 'ar' | 'ckb' | 'kmr'; labelKey: string; rtl: boolean }> = [
  { suf: 'en', labelKey: 'common.lang_en', rtl: false },
  { suf: 'ar', labelKey: 'common.lang_ar', rtl: true },
  { suf: 'ckb', labelKey: 'common.lang_sorani', rtl: true },
  { suf: 'kmr', labelKey: 'common.lang_badini', rtl: true },
]

export default function ContentPage({
  slug,
  titleKey,
  subtitleKey,
  contact = false,
}: {
  slug: string
  titleKey: string
  subtitleKey: string
  /**
   * K13 — show the contact-details editor. Passed only by the pages that are
   * actually a Contact page, so Terms and About are not given six boxes that
   * their screen has nowhere to render.
   */
  contact?: boolean
}) {
  const { t, locale } = useI18n()
  const { user } = useAuth()
  const toast = useToast()
  const empty: Content = {
    slug,
    title_en: '', title_ar: '', title_ckb: '', title_kmr: '',
    body_en: '', body_ar: '', body_ckb: '', body_kmr: '',
    logo_path: '', contact_phone: '', contact_whatsapp: '', contact_email: '',
    social_links: '',
    address_en: '', address_ar: '', address_ckb: '', address_kmr: '',
  }
  const [form, setForm] = useState<Content>(empty)
  const [sections, setSections] = useState<ContentSection[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  // True when the slug is valid but has no row yet — a hint, not an error.
  const [notYetCreated, setNotYetCreated] = useState(false)

  const amSuper = isSuperAdmin(user)

  // Loads the page and its sub-sections. Extracted from the effect because
  // save() re-runs it: the backend recomposes `body_*` from the sub-sections,
  // so the form would otherwise hold a body the server has already replaced.
  const load = useCallback(async () => {
    const res = await api.get<{ content: Content; sections?: ContentSection[] }>(`/api/content/${slug}`)
    setForm({ ...empty, ...res.data.content })
    setSections(res.data.sections ?? [])
    setErr(null)
    setNotYetCreated(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slug])

  useEffect(() => {
    if (!amSuper) { setLoading(false); return }
    let cancelled = false
    setLoading(true)
    load()
      .catch((e) => {
        if (cancelled) return
        // A 404 means this page has no row yet, not that anything is broken —
        // the admin PUT upserts, so saving the empty form below creates it.
        // Showing the red error box here made a brand-new page look like a
        // failure (which is exactly how humanitarian-work presented before it
        // was seeded in migration 096).
        if (isAxiosError(e) && e.response?.status === 404) {
          setForm(empty)
          setSections([])
          setErr(null)
          setNotYetCreated(true)
          return
        }
        setErr(describeError(e))
      })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [amSuper, slug, load])

  const set = (key: keyof Content) => (v: string) => setForm((f) => ({ ...f, [key]: v }))

  // K13 — recomputed on every keystroke so the message under a field appears
  // and clears as it is fixed, rather than only on submit. Only consulted on a
  // Contact page: the other pages have no contact boxes to be wrong.
  const contactErrors = contact ? validateContactFields(form) : {}
  const hasContactError = Object.keys(contactErrors).length > 0

  const save = async () => {
    // Never let a doomed request fire. The button is disabled below too; this
    // is the guard for the top-bar save action, which shares this function.
    if (hasContactError) {
      toast.error(t('content.fix_fields_first'))
      return
    }
    setSaving(true)
    try {
      // Order matters. The page PUT writes `body_*` verbatim; the sections PUT
      // then recomposes it from the sub-sections. Doing it the other way round
      // would let the stale body in `form` overwrite the composed one.
      await api.put(`/api/admin/content/${slug}`, form)
      await api.put(`/api/admin/content/${slug}/sections`, { sections })
      setNotYetCreated(false)
      // Re-read so the form shows what the server actually stored — the
      // composed body, and server-assigned sub-section ids.
      await load()
      // This one component backs eight pages, so a fixed message announced
      // "Terms & Conditions saved." after saving من نحن or اتصل بنا — naming a
      // page the admin had not opened. The row already carries its own title in
      // all four languages, so the confirmation names itself: reader's locale
      // first, English as the fallback the rest of this file uses, and a
      // page-less wording when the row genuinely has no title yet (a new page
      // saved before one was typed) so it can never read "Saved .".
      const pageTitle = (
        form[`title_${locale}` as keyof Content] as string | undefined
      )?.trim() || form.title_en?.trim()
      toast.success(
        pageTitle
          ? t('content.saved', { page: pageTitle })
          : t('content.saved_untitled'),
      )
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(false)
    }
  }

  // F3 — offer this page's save to the shared حفظ button in the top bar. This
  // one component backs eight sections (شروط الاستخدام, من نحن, اتصل بنا,
  // أعمالنا الإنسانية, and the About/Contact pages of دليل المدينة and الزواج),
  // so registering here is what makes the bar button real across all of them.
  //
  // Withheld while the page is loading, while a save is already in flight, and
  // for a non-Super-Admin — who sees the "restricted" panel instead of a form,
  // and for whom the backend would refuse the PUT anyway. The button is
  // disabled in each of those states rather than failing when pressed.
  useRegisterSaveAction(amSuper && !loading && !saving && !hasContactError ? save : null)

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
        <button className="btn primary" onClick={save} disabled={loading || saving || hasContactError}>
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
          {/* Composed server-side while sub-sections exist, so editing it here
              would be discarded on the next save. Explained rather than shown
              disabled: a greyed-out box full of text invites a bug report. */}
          {sections.length > 0 ? (
            <p className="hint">{t('content.body_from_sections')}</p>
          ) : (
            <label className="field">
              <span className="muted">{t('terms.field_body')}</span>
              <textarea
                rows={12}
                dir={rtl ? 'rtl' : 'ltr'}
                value={form[`body_${suf}` as keyof Content]}
                onChange={(e) => set(`body_${suf}` as keyof Content)(e.target.value)}
              />
            </label>
          )}
        </div>
      ))}

      {!loading && contact && (
        <ContentContactEditor
          values={form}
          onChange={(key, value) => set(key)(value)}
          errors={contactErrors}
          disabled={saving}
        />
      )}

      {!loading && (
        <ContentSectionsEditor
          sections={sections}
          onChange={setSections}
          disabled={saving}
        />
      )}
    </div>
  )
}
