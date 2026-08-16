// DonationTypesPage — admin CMS for the donor-facing donation types shown on
// the app's donate screen (M7). Add / edit (4 languages) / toggle active /
// reorder / delete. GET/POST/PATCH/reorder/DELETE /api/admin/donation-types.
//
// WHY THIS PAGE EXISTS
// The client asked for full control of the donation options from the dashboard
// "دون الحاجة إلى تحديث برمجي". Projects, editing/deleting projects and payment
// methods were already rows with pages like this one; the giving TYPE
// (general / zakat / sadaqah) was a hardcoded switch in Go, so adding a fourth
// meant a code change and a redeploy. Migration 103 made it a table and this is
// its screen.
//
// NOT the same thing as the donation *section* codes on /donation-codes — those
// are the internal routing namespaces (CAM-, GEN-, …). A type is what the donor
// says their gift is; a section is where the system files it.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'

type DonationType = {
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

export default function DonationTypesPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<DonationType[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState({ ...EMPTY_DRAFT })

  const load = () => {
    setLoading(true)
    api
      .get<{ items: DonationType[] }>('/api/admin/donation-types')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const patchItem = (id: number, patch: Partial<DonationType>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (d: DonationType) => {
    if (!d.name_en.trim()) {
      toast.error(t('donationTypes.need_en'))
      return
    }
    setSavingId(d.id)
    try {
      await api.patch(`/api/admin/donation-types/${d.id}`, {
        name_en: d.name_en,
        name_ar: d.name_ar,
        name_ckb: d.name_ckb,
        name_kmr: d.name_kmr,
        active: d.active,
      })
      toast.success(t('donationTypes.saved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!(await askToConfirm({ message: t('donationTypes.confirm_delete'), destructive: true }))) return
    try {
      await api.delete(`/api/admin/donation-types/${id}`)
      toast.success(t('donationTypes.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('donationTypes.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/donation-types', draft)
      toast.success(t('donationTypes.added'))
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
      await api.post('/api/admin/donation-types/reorder', {
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
          <h1>{t('donationTypes.title')}</h1>
          <p className="muted">{t('donationTypes.subtitle')}</p>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('donationTypes.add_new')}</h3>
        {/* The slug is derived from the English name on the server and is then
            immutable, because past donations already store it. Say so here
            rather than letting an operator discover it by renaming one. */}
        <p className="muted">{t('donationTypes.slug_hint')}</p>
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
          {adding ? t('common.saving') : t('donationTypes.add_new')}
        </button>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && items.length === 0 && !err && (
        <div className="card">
          <p className="muted">{t('donationTypes.empty')}</p>
        </div>
      )}

      {!loading &&
        items.map((d, i) => (
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
                  value={d[field] ?? ''}
                  onChange={(e) =>
                    patchItem(d.id, { [field]: e.target.value } as Partial<DonationType>)
                  }
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
              <span className="muted">{t('donationTypes.active')}</span>
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
  )
}
