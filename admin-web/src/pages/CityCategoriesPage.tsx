// CityCategoriesPage — the City Guide sub-category CMS, the second half of the
// spec's "Main and subcategory" field.
//
// The six sectors were curated; the sub-category was a free-text column whose
// live values included 'asdsa' and single Arabic letters. Each row here belongs
// to one sector. Add / edit (4 languages) / move between sectors / toggle
// active / reorder / delete.
// GET/POST/PATCH/reorder/DELETE /api/admin/city-categories.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import CmsItemCard from '../components/CmsItemCard'

type Category = {
  id: number
  slug: string
  sector_slug: string
  name_en: string
  name_ar: string
  name_ckb: string
  name_kmr: string
  display_order: number
  active: boolean
}

type NameField = 'name_en' | 'name_ar' | 'name_ckb' | 'name_kmr'

const LANGS: Array<{ field: NameField; labelKey: string; rtl: boolean }> = [
  { field: 'name_en', labelKey: 'common.lang_en', rtl: false },
  { field: 'name_ar', labelKey: 'common.lang_ar', rtl: true },
  { field: 'name_ckb', labelKey: 'common.lang_sorani', rtl: true },
  { field: 'name_kmr', labelKey: 'common.lang_badini', rtl: true },
]

const EMPTY_DRAFT = {
  name_en: '',
  name_ar: '',
  name_ckb: '',
  name_kmr: '',
  sector_slug: '',
}

type Sector = { slug: string; name_en: string }

export default function CityCategoriesPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Category[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState({ ...EMPTY_DRAFT })
  // The six sectors, so a sub-category is filed under a real one rather than
  // a typed slug that silently orphans it.
  const [sectors, setSectors] = useState<Sector[]>([])

  const load = () => {
    setLoading(true)
    api
      .get<{ items: Category[] }>('/api/admin/city-categories')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(load, [])
  useEffect(() => {
    api
      .get<{ items: Sector[] }>('/api/admin/city-sectors')
      .then((r) => {
        const items = r.data.items ?? []
        setSectors(items)
        setDraft((d) => (d.sector_slug ? d : { ...d, sector_slug: items[0]?.slug ?? '' }))
      })
      .catch(() => { /* picker falls back to the free-text value already set */ })
  }, [])

  const patchItem = (id: number, patch: Partial<Category>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (c: Category) => {
    if (!c.name_en.trim()) {
      toast.error(t('cityCategories.need_en'))
      return
    }
    setSavingId(c.id)
    try {
      await api.patch(`/api/admin/city-categories/${c.id}`, {
        name_en: c.name_en,
        name_ar: c.name_ar,
        name_ckb: c.name_ckb,
        name_kmr: c.name_kmr,
        sector_slug: c.sector_slug,
        active: c.active,
      })
      toast.success(t('cityCategories.saved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!(await askToConfirm({ message: t('cityCategories.confirm_delete'), destructive: true }))) return
    try {
      await api.delete(`/api/admin/city-categories/${id}`)
      toast.success(t('cityCategories.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('cityCategories.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/city-categories', draft)
      toast.success(t('cityCategories.added'))
      setDraft({ ...EMPTY_DRAFT })
      load()
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
      await api.post('/api/admin/city-categories/reorder', {
        ids: reordered.map((x) => x.id),
      })
    } catch (e) {
      toast.error(describeError(e))
      load()
    }
  }

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('cityCategories.title')}</h1>
          <p className="muted">{t('cityCategories.subtitle')}</p>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('cityCategories.add_new')}</h3>
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
        <label className="field">
          <span className="muted">{t('cityCategories.sector')}</span>
          <select
            value={draft.sector_slug}
            onChange={(e) => setDraft((d) => ({ ...d, sector_slug: e.target.value }))}
          >
            {sectors.map((sc) => (
              <option key={sc.slug} value={sc.slug}>{sc.name_en}</option>
            ))}
          </select>
        </label>
        <button className="btn primary" onClick={addNew} disabled={adding}>
          {adding ? t('common.saving') : t('cityCategories.add_new')}
        </button>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading &&
        items.map((c, i) => (
          <CmsItemCard
            key={c.id}
            title={c.name_en || c.slug}
            actions={
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
            }
          >
            {LANGS.map(({ field, labelKey, rtl }) => (
              <label className="field" key={field}>
                <span className="muted">{t(labelKey)}</span>
                <input
                  type="text"
                  dir={rtl ? 'rtl' : 'ltr'}
                  value={c[field] ?? ''}
                  onChange={(e) => patchItem(c.id, { [field]: e.target.value } as Partial<Category>)}
                />
              </label>
            ))}
            <label className="field">
              <span className="muted">{t('cityCategories.sector')}</span>
              <select
                value={c.sector_slug ?? ''}
                onChange={(e) => patchItem(c.id, { sector_slug: e.target.value })}
              >
                {sectors.map((sc) => (
                  <option key={sc.slug} value={sc.slug}>{sc.name_en}</option>
                ))}
              </select>
            </label>
            <label
              className="field"
              style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}
            >
              <input
                type="checkbox"
                checked={c.active}
                onChange={(e) => patchItem(c.id, { active: e.target.checked })}
              />
              <span className="muted">{t('cityCategories.active')}</span>
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
          </CmsItemCard>
        ))}
    </div>
  )
}
