// MarketplaceCategoriesPage — admin CMS for the marketplace product categories
// (#28). Add / edit (4 languages) / toggle active / reorder / delete.
// GET/POST/PATCH/reorder/DELETE /api/admin/marketplace/categories.
import { useEffect, useRef, useState } from 'react'
import {
  UtensilsCrossed, ShoppingBasket, Shirt, Watch, Cpu, Home, Sparkles,
  ToyBrick, BookOpen, HeartPulse, Dumbbell, Wrench, Gift, PawPrint,
  PenLine, Package, Check, ChevronDown, type LucideIcon,
} from 'lucide-react'
import { api, describeError } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import CmsItemCard from '../components/CmsItemCard'

// #41080 — fixed icon vocabulary, kept in lockstep with the backend's
// marketplacecategories.ValidIconKeys (Go) and the app's icon_key lookup
// (humanitarian/lib/modules/marketplace/widgets/category_icons.dart). Add a
// key to all three together, never just one — an unrecognised key falls
// back to "other" on every side rather than rendering nothing.
export const ICON_OPTIONS: Array<{ key: string; icon: LucideIcon; labelKey: string }> = [
  { key: 'food', icon: UtensilsCrossed, labelKey: 'marketplaceCategories.icon.food' },
  { key: 'groceries', icon: ShoppingBasket, labelKey: 'marketplaceCategories.icon.groceries' },
  { key: 'clothing', icon: Shirt, labelKey: 'marketplaceCategories.icon.clothing' },
  { key: 'accessories', icon: Watch, labelKey: 'marketplaceCategories.icon.accessories' },
  { key: 'electronics', icon: Cpu, labelKey: 'marketplaceCategories.icon.electronics' },
  { key: 'home', icon: Home, labelKey: 'marketplaceCategories.icon.home' },
  { key: 'beauty', icon: Sparkles, labelKey: 'marketplaceCategories.icon.beauty' },
  { key: 'toys', icon: ToyBrick, labelKey: 'marketplaceCategories.icon.toys' },
  { key: 'books', icon: BookOpen, labelKey: 'marketplaceCategories.icon.books' },
  { key: 'health', icon: HeartPulse, labelKey: 'marketplaceCategories.icon.health' },
  { key: 'sports', icon: Dumbbell, labelKey: 'marketplaceCategories.icon.sports' },
  { key: 'tools', icon: Wrench, labelKey: 'marketplaceCategories.icon.tools' },
  { key: 'gifts', icon: Gift, labelKey: 'marketplaceCategories.icon.gifts' },
  { key: 'pets', icon: PawPrint, labelKey: 'marketplaceCategories.icon.pets' },
  { key: 'stationery', icon: PenLine, labelKey: 'marketplaceCategories.icon.stationery' },
  { key: 'other', icon: Package, labelKey: 'marketplaceCategories.icon.other' },
]

function iconFor(key: string): LucideIcon {
  return ICON_OPTIONS.find((o) => o.key === key)?.icon ?? Package
}

// Collapsed by default — a plain trigger button naming the current icon,
// which opens a dropdown of the 16 choices on click. Owner feedback on the
// first version (an always-open 16-icon grid with no visible "which one am
// I on" state, per row, times 22 rows): unclear which icon was selected,
// and it took up permanent space it didn't need to.
function IconPicker({ value, onChange }: { value: string; onChange: (key: string) => void }) {
  const { t } = useI18n()
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  const current = ICON_OPTIONS.find((o) => o.key === value) ?? ICON_OPTIONS[ICON_OPTIONS.length - 1]
  const CurrentIcon = current.icon

  useEffect(() => {
    if (!open) return
    const onDocClick = (e: MouseEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false)
    }
    const onEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    document.addEventListener('keydown', onEscape)
    return () => {
      document.removeEventListener('mousedown', onDocClick)
      document.removeEventListener('keydown', onEscape)
    }
  }, [open])

  return (
    <div className="field" ref={rootRef} style={{ position: 'relative' }}>
      <span className="muted">{t('marketplaceCategories.icon_label')}</span>
      <button
        type="button"
        className="btn"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        style={{ display: 'inline-flex', alignItems: 'center', gap: 8, width: 'fit-content' }}
      >
        <CurrentIcon size={18} />
        <span>{t(current.labelKey)}</span>
        <ChevronDown size={14} style={{ opacity: 0.7 }} />
      </button>

      {open && (
        <div
          className="card"
          style={{
            position: 'absolute',
            top: '100%',
            insetInlineStart: 0,
            marginTop: 4,
            zIndex: 20,
            display: 'grid',
            gridTemplateColumns: 'repeat(4, 1fr)',
            gap: 6,
            width: 240,
            boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
          }}
        >
          {ICON_OPTIONS.map(({ key, icon: Icon, labelKey }) => {
            const selected = key === value
            return (
              <button
                key={key}
                type="button"
                // Unselected tiles are `secondary` (neutral grey) — every
                // <button> defaults to the same solid accent green
                // (index.css), so leaving that default on all 16 tiles is
                // what made the selected one impossible to pick out. Only
                // the selected tile keeps the green.
                className={selected ? 'btn' : 'btn secondary'}
                title={t(labelKey)}
                onClick={() => {
                  onChange(key)
                  setOpen(false)
                }}
                style={{
                  position: 'relative',
                  width: 48,
                  height: 48,
                  padding: 0,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                <Icon size={18} />
                {selected && (
                  <Check
                    size={12}
                    strokeWidth={3}
                    style={{
                      position: 'absolute',
                      top: 2,
                      insetInlineEnd: 2,
                      background: '#fff',
                      color: 'var(--color-accent, #10b981)',
                      borderRadius: '999px',
                    }}
                  />
                )}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

type Category = {
  id: number
  slug: string
  name_en: string
  name_ar: string
  name_ckb: string
  name_kmr: string
  display_order: number
  active: boolean
  icon_key: string
}

type NameField = 'name_en' | 'name_ar' | 'name_ckb' | 'name_kmr'

const LANGS: Array<{ field: NameField; labelKey: string; rtl: boolean }> = [
  { field: 'name_en', labelKey: 'common.lang_en', rtl: false },
  { field: 'name_ar', labelKey: 'common.lang_ar', rtl: true },
  { field: 'name_ckb', labelKey: 'common.lang_sorani', rtl: true },
  { field: 'name_kmr', labelKey: 'common.lang_badini', rtl: true },
]

const EMPTY_DRAFT = { name_en: '', name_ar: '', name_ckb: '', name_kmr: '', icon_key: 'other' }

export default function MarketplaceCategoriesPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Category[]>([])
  // `loading` is derived from which reload tick last came back, so the fetch
  // effect below sets nothing synchronously. `reload()` bumps the tick, which
  // is what re-runs the effect.
  const [tick, setTick] = useState(0)
  const [loadedTick, setLoadedTick] = useState(-1)
  const loading = loadedTick !== tick
  const reload = () => setTick((n) => n + 1)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState({ ...EMPTY_DRAFT })

  const load = () => {
    api
      .get<{ items: Category[] }>('/api/admin/marketplace/categories')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoadedTick(tick))
  }
  useEffect(load, [tick])

  const patchItem = (id: number, patch: Partial<Category>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (c: Category) => {
    if (!c.name_en.trim()) {
      toast.error(t('marketplaceCategories.need_en'))
      return
    }
    setSavingId(c.id)
    try {
      await api.patch(`/api/admin/marketplace/categories/${c.id}`, {
        name_en: c.name_en,
        name_ar: c.name_ar,
        name_ckb: c.name_ckb,
        name_kmr: c.name_kmr,
        active: c.active,
        icon_key: c.icon_key,
      })
      toast.success(t('marketplaceCategories.saved'))
      reload()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!(await askToConfirm({ message: t('marketplaceCategories.confirm_delete'), destructive: true }))) return
    try {
      await api.delete(`/api/admin/marketplace/categories/${id}`)
      toast.success(t('marketplaceCategories.deleted'))
      reload()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('marketplaceCategories.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/marketplace/categories', draft)
      toast.success(t('marketplaceCategories.added'))
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
      await api.post('/api/admin/marketplace/categories/reorder', {
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
          <h1>{t('marketplaceCategories.title')}</h1>
          <p className="muted">{t('marketplaceCategories.subtitle')}</p>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('marketplaceCategories.add_new')}</h3>
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
        <IconPicker value={draft.icon_key} onChange={(icon_key) => setDraft((d) => ({ ...d, icon_key }))} />
        <button className="btn primary" onClick={addNew} disabled={adding}>
          {adding ? t('common.saving') : t('marketplaceCategories.add_new')}
        </button>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading &&
        items.map((c, i) => {
          const RowIcon = iconFor(c.icon_key)
          return (
          <CmsItemCard
            key={c.id}
            title={
              <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <RowIcon size={16} /> {c.name_en || c.slug}
              </span>
            }
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
            <IconPicker
              value={c.icon_key}
              onChange={(icon_key) => patchItem(c.id, { icon_key })}
            />
            <label
              className="field"
              style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}
            >
              <input
                type="checkbox"
                checked={c.active}
                onChange={(e) => patchItem(c.id, { active: e.target.checked })}
              />
              <span className="muted">{t('marketplaceCategories.active')}</span>
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
          )
        })}
    </div>
  )
}
