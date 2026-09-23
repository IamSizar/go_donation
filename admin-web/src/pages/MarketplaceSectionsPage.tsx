// MarketplaceSectionsPage — admin CMS for store "sections": named shelves
// with a cover image, shown as a grid on the app's store page. Replaces
// marketplace categories as how a product is grouped: a product now belongs
// to at most one section, assigned from the product's own edit form (the
// "Section" dropdown in MarketplacePage.tsx) — not from here.
// GET/POST/PATCH/reorder/DELETE /api/admin/marketplace/sections.
import { useEffect, useState } from 'react'
import { api, describeError, assetUrl } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import CmsItemCard from '../components/CmsItemCard'
import FileInput from '../components/FileInput'

type Section = {
  id: number
  slug: string
  name_en: string
  name_ar: string
  name_ckb: string
  name_kmr: string
  cover_image_path: string
  display_order: number
  active: boolean
  starts_at: string | null
  ends_at: string | null
  product_count: number
}

type NameField = 'name_en' | 'name_ar' | 'name_ckb' | 'name_kmr'

const LANGS: Array<{ field: NameField; labelKey: string; rtl: boolean }> = [
  { field: 'name_en', labelKey: 'common.lang_en', rtl: false },
  { field: 'name_ar', labelKey: 'common.lang_ar', rtl: true },
  { field: 'name_ckb', labelKey: 'common.lang_sorani', rtl: true },
  { field: 'name_kmr', labelKey: 'common.lang_badini', rtl: true },
]

const EMPTY_DRAFT = {
  name_en: '', name_ar: '', name_ckb: '', name_kmr: '', cover_image_path: '',
}

export default function MarketplaceSectionsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Section[]>([])
  const [tick, setTick] = useState(0)
  const [loadedTick, setLoadedTick] = useState(-1)
  const loading = loadedTick !== tick
  const reload = () => setTick((n) => n + 1)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState({ ...EMPTY_DRAFT })

  useEffect(() => {
    api
      .get<{ items: Section[] }>('/api/admin/marketplace/sections')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoadedTick(tick))
  }, [tick])

  const patchItem = (id: number, patch: Partial<Section>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (sec: Section) => {
    if (!sec.name_en.trim()) {
      toast.error(t('marketplaceSections.need_en'))
      return
    }
    setSavingId(sec.id)
    try {
      await api.patch(`/api/admin/marketplace/sections/${sec.id}`, {
        name_en: sec.name_en,
        name_ar: sec.name_ar,
        name_ckb: sec.name_ckb,
        name_kmr: sec.name_kmr,
        cover_image_path: sec.cover_image_path,
        active: sec.active,
      })
      toast.success(t('marketplaceSections.saved'))
      reload()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!(await askToConfirm({ message: t('marketplaceSections.confirm_delete'), destructive: true }))) return
    try {
      await api.delete(`/api/admin/marketplace/sections/${id}`)
      toast.success(t('marketplaceSections.deleted'))
      reload()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('marketplaceSections.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/marketplace/sections', draft)
      toast.success(t('marketplaceSections.added'))
      setDraft({ ...EMPTY_DRAFT })
      reload()
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
      await api.post('/api/admin/marketplace/sections/reorder', {
        ids: reordered.map((x) => x.id),
      })
    } catch (e) {
      toast.error(describeError(e))
      reload()
    }
  }

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('marketplaceSections.title')}</h1>
          <p className="muted">{t('marketplaceSections.subtitle')}</p>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('marketplaceSections.add_new')}</h3>
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
          <span className="muted">{t('marketplaceSections.cover_image')}</span>
          <FileInput
            value={draft.cover_image_path}
            onChange={(cover_image_path) => setDraft((d) => ({ ...d, cover_image_path }))}
            crop
          />
        </label>
        <button className="btn primary" onClick={addNew} disabled={adding}>
          {adding ? t('common.saving') : t('marketplaceSections.add_new')}
        </button>
        <p className="muted">{t('marketplaceSections.products_after_create')}</p>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading &&
        items.map((sec, i) => (
          <CmsItemCard
            key={sec.id}
            title={
              <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                {sec.cover_image_path && (
                  <img
                    src={assetUrl(sec.cover_image_path)}
                    alt=""
                    style={{ width: 28, height: 28, objectFit: 'cover', borderRadius: 6 }}
                  />
                )}
                {sec.name_en || sec.slug}
                <span className="muted">
                  {t('marketplaceSections.product_count').replace('{n}', String(sec.product_count))}
                </span>
              </span>
            }
            actions={
              <div style={{ display: 'flex', gap: 6 }}>
                <button className="btn" onClick={() => move(i, -1)} disabled={i === 0}>
                  ↑
                </button>
                <button className="btn" onClick={() => move(i, 1)} disabled={i === items.length - 1}>
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
                  value={sec[field] ?? ''}
                  onChange={(e) => patchItem(sec.id, { [field]: e.target.value } as Partial<Section>)}
                />
              </label>
            ))}
            <label className="field">
              <span className="muted">{t('marketplaceSections.cover_image')}</span>
              <FileInput
                value={sec.cover_image_path}
                onChange={(cover_image_path) => patchItem(sec.id, { cover_image_path })}
                crop
              />
            </label>
            <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <input
                type="checkbox"
                checked={sec.active}
                onChange={(e) => patchItem(sec.id, { active: e.target.checked })}
              />
              <span className="muted">{t('marketplaceSections.active')}</span>
            </label>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn primary" onClick={() => save(sec)} disabled={savingId === sec.id}>
                {savingId === sec.id ? t('common.saving') : t('common.save')}
              </button>
              <button className="btn danger" onClick={() => remove(sec.id)}>
                {t('common.delete')}
              </button>
            </div>
          </CmsItemCard>
        ))}
    </div>
  )
}
