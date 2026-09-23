// MarketplaceSectionsPage — admin CMS for store "sections": named shelves
// with a cover image that any number of existing marketplace products can be
// added to (e.g. "Clothing"). Unlike marketplace categories (a single tag a
// seller picks per product), a section is admin-curated and many-to-many —
// see backend migration 133.
// GET/POST/PATCH/reorder/DELETE /api/admin/marketplace/sections, plus
// GET/PUT /api/admin/marketplace/sections/:id/products for membership.
import { useEffect, useMemo, useState } from 'react'
import { api, describeError, assetUrl } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import CmsItemCard from '../components/CmsItemCard'
import FileInput from '../components/FileInput'
import type { AdminPageResp, Product } from '../lib/api-types'

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

// ProductPicker — a search box + checkbox list over the existing admin
// products endpoint. Not the generic EditModal `multiselect` field: that
// type expects a fixed `options` list, and the product catalogue is neither
// fixed nor small enough to preload.
function ProductPicker({
  selected,
  onToggle,
}: {
  selected: Set<number>
  onToggle: (id: number) => void
}) {
  const { t } = useI18n()
  const [q, setQ] = useState('')
  const [items, setItems] = useState<Product[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    let cancelled = false
    const handle = setTimeout(() => {
      setLoading(true)
      api
        .get<AdminPageResp<Product>>('/api/admin/marketplace/products', {
          params: { page: 1, per_page: 20, status: 'all', q: q || undefined },
        })
        .then((res) => { if (!cancelled) setItems(res.data.items ?? []) })
        .finally(() => { if (!cancelled) setLoading(false) })
    }, 300)
    return () => { cancelled = true; clearTimeout(handle) }
  }, [q])

  return (
    <div className="field" style={{ width: '100%' }}>
      <span className="muted">{t('marketplaceSections.products_label')}</span>
      <input
        type="text"
        placeholder={t('marketplaceSections.search_products')}
        value={q}
        onChange={(e) => setQ(e.target.value)}
      />
      {loading && <p className="muted">{t('common.loading')}</p>}
      <div
        className="card"
        style={{ maxHeight: 260, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 4 }}
      >
        {items.map((p) => (
          <label
            key={p.id}
            style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0' }}
          >
            <input
              type="checkbox"
              checked={selected.has(p.id)}
              onChange={() => onToggle(p.id)}
            />
            <span>{p.name}</span>
            <span className="muted">#{p.id}</span>
          </label>
        ))}
        {!loading && items.length === 0 && <p className="muted">{t('marketplaceSections.no_products_found')}</p>}
      </div>
      <p className="muted">
        {t('marketplaceSections.selected_count').replace('{n}', String(selected.size))}
      </p>
    </div>
  )
}

function SectionProducts({ sectionId }: { sectionId: number }) {
  const { t } = useI18n()
  const toast = useToast()
  const [selected, setSelected] = useState<Set<number>>(new Set())
  const [initial, setInitial] = useState<Set<number>>(new Set())
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    api
      .get<{ product_ids: number[] }>(`/api/admin/marketplace/sections/${sectionId}/products`)
      .then((res) => {
        const ids = new Set(res.data.product_ids ?? [])
        setSelected(ids)
        setInitial(ids)
      })
  }, [sectionId])

  const dirty = useMemo(() => {
    if (selected.size !== initial.size) return true
    for (const id of selected) if (!initial.has(id)) return true
    return false
  }, [selected, initial])

  const toggle = (id: number) => {
    setSelected((s) => {
      const next = new Set(s)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const save = async () => {
    setSaving(true)
    try {
      await api.put(`/api/admin/marketplace/sections/${sectionId}/products`, {
        product_ids: [...selected],
      })
      setInitial(selected)
      toast.success(t('marketplaceSections.products_saved'))
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="stack" style={{ gap: 8 }}>
      <ProductPicker selected={selected} onToggle={toggle} />
      <button className="btn primary" onClick={save} disabled={saving || !dirty} style={{ width: 'fit-content' }}>
        {saving ? t('common.saving') : t('marketplaceSections.save_products')}
      </button>
    </div>
  )
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
  const [expandedId, setExpandedId] = useState<number | null>(null)

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
              <button
                className="btn secondary"
                onClick={() => setExpandedId((id) => (id === sec.id ? null : sec.id))}
              >
                {expandedId === sec.id
                  ? t('marketplaceSections.hide_products')
                  : t('marketplaceSections.manage_products')}
              </button>
            </div>
            {expandedId === sec.id && <SectionProducts sectionId={sec.id} />}
          </CmsItemCard>
        ))}
    </div>
  )
}
