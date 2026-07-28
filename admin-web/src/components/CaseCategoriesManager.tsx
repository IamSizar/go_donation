// CaseCategoriesManager — admin CMS for the beneficiary-case category list
// that powers the app's Home "Quick Filter Capsules" (Orphan Sponsorship,
// Widow Support, Food Baskets, etc). Add / edit (4 languages) / toggle
// active / reorder / delete. GET/POST/PATCH/reorder/DELETE
// /api/admin/case-categories.
//
// Rendered as an in-page modal from BeneficiaryPage's Cases tab rather than
// its own sidebar route — the client specifically complained the admin nav
// already has too many one-off "backend module" entries (Donation Codes,
// Payment Methods, Marketplace Categories, Media Categories, ...), so this
// stays nested where it's actually used instead of adding another one.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import type { CaseCategory } from '../lib/api-types'

type NameField = 'name_en' | 'name_ar' | 'name_ckb' | 'name_kmr'

const LANGS: Array<{ field: NameField; labelKey: string; rtl: boolean }> = [
  { field: 'name_en', labelKey: 'common.lang_en', rtl: false },
  { field: 'name_ar', labelKey: 'common.lang_ar', rtl: true },
  { field: 'name_ckb', labelKey: 'common.lang_sorani', rtl: true },
  { field: 'name_kmr', labelKey: 'common.lang_badini', rtl: true },
]

const EMPTY_DRAFT = { name_en: '', name_ar: '', name_ckb: '', name_kmr: '' }

type Props = {
  open: boolean
  onClose: () => void
  // Called after any add/edit/delete/reorder that succeeds, so the caller
  // can refresh its own category dropdown options.
  onChanged?: () => void
}

export default function CaseCategoriesManager({ open, onClose, onChanged }: Props) {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<CaseCategory[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState({ ...EMPTY_DRAFT })

  const load = () => {
    setLoading(true)
    api
      .get<{ items: CaseCategory[] }>('/api/admin/case-categories')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(() => {
    if (open) load()
  }, [open])

  const patchItem = (id: number, patch: Partial<CaseCategory>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (c: CaseCategory) => {
    if (!c.name_en.trim()) {
      toast.error(t('caseCategories.need_en'))
      return
    }
    setSavingId(c.id)
    try {
      await api.patch(`/api/admin/case-categories/${c.id}`, {
        name_en: c.name_en,
        name_ar: c.name_ar,
        name_ckb: c.name_ckb,
        name_kmr: c.name_kmr,
        active: c.active,
      })
      toast.success(t('caseCategories.saved'))
      load()
      onChanged?.()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!window.confirm(t('caseCategories.confirm_delete'))) return
    try {
      await api.delete(`/api/admin/case-categories/${id}`)
      toast.success(t('caseCategories.deleted'))
      load()
      onChanged?.()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('caseCategories.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/case-categories', draft)
      toast.success(t('caseCategories.added'))
      setDraft({ ...EMPTY_DRAFT })
      load()
      onChanged?.()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setAdding(false)
    }
  }

  const move = async (index: number, dir: -1 | 1) => {
    const next = index + dir
    if (next < 0 || next >= items.length) return
    const reordered = [...items]
    const [row] = reordered.splice(index, 1)
    reordered.splice(next, 0, row)
    setItems(reordered)
    try {
      await api.post('/api/admin/case-categories/reorder', {
        ids: reordered.map((x) => x.id),
      })
      onChanged?.()
    } catch (e) {
      toast.error(describeError(e))
      load()
    }
  }

  if (!open) return null

  return (
    <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="modal-card" role="dialog" aria-modal="true" aria-label={t('caseCategories.title')}>
        <div className="modal-head">
          <h2>{t('caseCategories.title')}</h2>
          <button className="icon" onClick={onClose} aria-label={t('common.close')}>×</button>
        </div>
        <div className="modal-body">
          <p className="muted">{t('caseCategories.subtitle')}</p>
          {err && <div className="error-box">{err}</div>}

          <div className="card">
            <h3>{t('caseCategories.add_new')}</h3>
            {LANGS.map(({ field, labelKey, rtl }) => (
              <label className="field" key={field}>
                <span className="muted">{t(labelKey)}</span>
                <input
                  type="text"
                  dir={rtl ? 'rtl' : 'ltr'}
                  value={draft[field]}
                  onChange={(e) => setDraft((d) => ({ ...d, [field]: e.target.value }))}
                />
              </label>
            ))}
            <button className="btn primary" onClick={addNew} disabled={adding}>
              {adding ? t('common.saving') : t('caseCategories.add_new')}
            </button>
          </div>

          {loading && <p className="muted">{t('common.loading')}</p>}

          {!loading &&
            items.map((c, i) => (
              <div className="card" key={c.id}>
                <div className="page-head">
                  <h3>{c.name_en || c.slug}</h3>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button className="btn" onClick={() => move(i, -1)} disabled={i === 0}>
                      ↑
                    </button>
                    <button
                      className="btn"
                      onClick={() => move(i, 1)}
                      disabled={i === items.length - 1}
                    >
                      ↓
                    </button>
                  </div>
                </div>
                {LANGS.map(({ field, labelKey, rtl }) => (
                  <label className="field" key={field}>
                    <span className="muted">{t(labelKey)}</span>
                    <input
                      type="text"
                      dir={rtl ? 'rtl' : 'ltr'}
                      value={c[field] ?? ''}
                      onChange={(e) => patchItem(c.id, { [field]: e.target.value } as Partial<CaseCategory>)}
                    />
                  </label>
                ))}
                <label
                  className="field"
                  style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}
                >
                  <input
                    type="checkbox"
                    checked={c.active}
                    onChange={(e) => patchItem(c.id, { active: e.target.checked })}
                  />
                  <span className="muted">{t('caseCategories.active')}</span>
                </label>
                <div style={{ display: 'flex', gap: 8 }}>
                  <button
                    className="btn primary"
                    onClick={() => save(c)}
                    disabled={savingId === c.id}
                  >
                    {savingId === c.id ? t('common.saving') : t('common.save')}
                  </button>
                  <button className="btn danger" onClick={() => remove(c.id)}>
                    {t('common.delete')}
                  </button>
                </div>
              </div>
            ))}
        </div>
      </div>
    </div>
  )
}
