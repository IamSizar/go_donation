// DistrictsManager — admin CMS for the registration form's Nineveh
// district/neighborhood pickers (OPOS #25271). Add / edit (4 languages) /
// toggle active / reorder / delete, one group at a time.
// GET/POST/PATCH/reorder/DELETE /api/admin/districts.
//
// Rendered as an in-page modal (same convention as CaseCategoriesManager)
// rather than its own sidebar route — the client specifically complained the
// admin nav already has too many one-off "backend module" entries, so this
// stays nested where it's actually used instead of adding another one.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import type { District } from '../lib/api-types'

type NameField = 'name_en' | 'name_ar' | 'name_ckb' | 'name_kmr'

const LANGS: Array<{ field: NameField; labelKey: string; rtl: boolean }> = [
  { field: 'name_en', labelKey: 'common.lang_en', rtl: false },
  { field: 'name_ar', labelKey: 'common.lang_ar', rtl: true },
  { field: 'name_ckb', labelKey: 'common.lang_sorani', rtl: true },
  { field: 'name_kmr', labelKey: 'common.lang_badini', rtl: true },
]

const GROUPS = [
  { key: 'nineveh_district', labelKey: 'districts.group_district' },
  { key: 'nineveh_neighborhood_left', labelKey: 'districts.group_neighborhood_left' },
  { key: 'nineveh_neighborhood_right', labelKey: 'districts.group_neighborhood_right' },
] as const

const EMPTY_DRAFT = { name_en: '', name_ar: '', name_ckb: '', name_kmr: '' }

type Props = {
  open: boolean
  onClose: () => void
  // Called after any add/edit/delete/reorder that succeeds, so the caller
  // can refresh its own district dropdown options.
  onChanged?: () => void
}

export default function DistrictsManager({ open, onClose, onChanged }: Props) {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<District[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState({ ...EMPTY_DRAFT })
  const [group, setGroup] = useState<(typeof GROUPS)[number]['key']>(GROUPS[0].key)

  const load = () => {
    setLoading(true)
    api
      .get<{ items: District[] }>('/api/admin/districts')
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

  const visible = items.filter((d) => d.group_key === group)

  const patchItem = (id: number, patch: Partial<District>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (d: District) => {
    if (!d.name_en.trim()) {
      toast.error(t('districts.need_en'))
      return
    }
    setSavingId(d.id)
    try {
      await api.patch(`/api/admin/districts/${d.id}`, {
        name_en: d.name_en,
        name_ar: d.name_ar,
        name_ckb: d.name_ckb,
        name_kmr: d.name_kmr,
        active: d.active,
      })
      toast.success(t('districts.saved'))
      load()
      onChanged?.()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!(await askToConfirm({ message: t('districts.confirm_delete'), destructive: true }))) return
    try {
      await api.delete(`/api/admin/districts/${id}`)
      toast.success(t('districts.deleted'))
      load()
      onChanged?.()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('districts.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/districts', { ...draft, group_key: group })
      toast.success(t('districts.added'))
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
    if (next < 0 || next >= visible.length) return
    const reordered = [...visible]
    const [row] = reordered.splice(index, 1)
    reordered.splice(next, 0, row)
    // Only this group's ids move — the other two groups' display_order is
    // untouched by a request scoped to this group's id list.
    setItems((xs) => [...xs.filter((x) => x.group_key !== group), ...reordered])
    try {
      await api.post('/api/admin/districts/reorder', {
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
      <div className="modal-card" role="dialog" aria-modal="true" aria-label={t('districts.title')}>
        <div className="modal-head">
          <h2>{t('districts.title')}</h2>
          <button className="icon" onClick={onClose} aria-label={t('common.close')}>×</button>
        </div>
        <div className="modal-body">
          <p className="muted">{t('districts.subtitle')}</p>
          {err && <div className="error-box">{err}</div>}

          <div className="row" style={{ marginBottom: 12 }}>
            <select value={group} onChange={(e) => setGroup(e.target.value as typeof group)} style={{ width: 'auto' }}>
              {GROUPS.map((g) => (
                <option key={g.key} value={g.key}>{t(g.labelKey)}</option>
              ))}
            </select>
          </div>

          <div className="card">
            <h3>{t('districts.add_new')}</h3>
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
              {adding ? t('common.saving') : t('districts.add_new')}
            </button>
          </div>

          {loading && <p className="muted">{t('common.loading')}</p>}

          {!loading &&
            visible.map((d, i) => (
              <div className="card" key={d.id}>
                <div className="page-head">
                  <h3>{d.name_en || d.slug}</h3>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button className="btn" onClick={() => move(i, -1)} disabled={i === 0}>
                      ↑
                    </button>
                    <button
                      className="btn"
                      onClick={() => move(i, 1)}
                      disabled={i === visible.length - 1}
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
                      value={d[field] ?? ''}
                      onChange={(e) => patchItem(d.id, { [field]: e.target.value } as Partial<District>)}
                    />
                  </label>
                ))}
                <label
                  className="field"
                  style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}
                >
                  <input
                    type="checkbox"
                    checked={d.active}
                    onChange={(e) => patchItem(d.id, { active: e.target.checked })}
                  />
                  <span className="muted">{t('districts.active')}</span>
                </label>
                <div style={{ display: 'flex', gap: 8 }}>
                  <button
                    className="btn primary"
                    onClick={() => save(d)}
                    disabled={savingId === d.id}
                  >
                    {savingId === d.id ? t('common.saving') : t('common.save')}
                  </button>
                  <button className="btn danger" onClick={() => remove(d.id)}>
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
