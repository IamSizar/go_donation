// CitySectorsPage — admin CMS for the City Guide sectors a place is grouped
// under (#29). Add / edit (4 languages) / toggle active / reorder / delete.
// GET/POST/PATCH/reorder/DELETE /api/admin/city-sectors. Mirrors the
// ProjectCategoriesPage CMS pattern.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Sector = {
  id: number
  slug: string
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

const EMPTY_DRAFT = { name_en: '', name_ar: '', name_ckb: '', name_kmr: '' }

export default function CitySectorsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Sector[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState({ ...EMPTY_DRAFT })

  const load = () => {
    setLoading(true)
    api
      .get<{ items: Sector[] }>('/api/admin/city-sectors')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const patchItem = (id: number, patch: Partial<Sector>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (c: Sector) => {
    if (!c.name_en.trim()) {
      toast.error(t('citySectors.need_en'))
      return
    }
    setSavingId(c.id)
    try {
      await api.patch(`/api/admin/city-sectors/${c.id}`, {
        name_en: c.name_en,
        name_ar: c.name_ar,
        name_ckb: c.name_ckb,
        name_kmr: c.name_kmr,
        active: c.active,
      })
      toast.success(t('citySectors.saved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!window.confirm(t('citySectors.confirm_delete'))) return
    try {
      await api.delete(`/api/admin/city-sectors/${id}`)
      toast.success(t('citySectors.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('citySectors.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/city-sectors', draft)
      toast.success(t('citySectors.added'))
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
      await api.post('/api/admin/city-sectors/reorder', {
        ids: reordered.map((x) => x.id),
      })
    } catch (e) {
      toast.error(describeError(e))
      load()
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('citySectors.title')}</h1>
          <p className="muted">{t('citySectors.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('citySectors.add_new')}</h3>
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
          {adding ? t('common.saving') : t('citySectors.add_new')}
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
                  onChange={(e) => patchItem(c.id, { [field]: e.target.value } as Partial<Sector>)}
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
              <span className="muted">{t('citySectors.active')}</span>
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
  )
}
