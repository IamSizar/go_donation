// MarriageSubscriptionsPage — client note "Subscription": a dynamic,
// admin-manageable package list (replacing the old fixed 5-tier + settings-
// price mechanism) plus a queue to confirm/reject pending cash/bank
// purchases. Same CRUD shape as Payment Methods.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Package = {
  id: number
  slug: string
  name_en: string; name_ar: string; name_ckb: string; name_kmr: string
  description_en: string; description_ar: string; description_ckb: string; description_kmr: string
  price_iqd: number
  display_order: number
  active: boolean
}

type Draft = Omit<Package, 'id' | 'display_order'>

type Purchase = {
  id: number
  profile_id: number
  user_id: number
  package_id: number
  package_slug: string
  package_name_en: string
  price_iqd: number
  payment_method: string
  status: 'pending' | 'paid' | 'rejected'
  created_at: string
  confirmed_at?: string | null
}

const LANGS: Array<{ suf: 'en' | 'ar' | 'ckb' | 'kmr'; labelKey: string; rtl: boolean }> = [
  { suf: 'en', labelKey: 'common.lang_en', rtl: false },
  { suf: 'ar', labelKey: 'common.lang_ar', rtl: true },
  { suf: 'ckb', labelKey: 'common.lang_sorani', rtl: true },
  { suf: 'kmr', labelKey: 'common.lang_badini', rtl: true },
]

const EMPTY_DRAFT: Draft = {
  slug: '',
  name_en: '', name_ar: '', name_ckb: '', name_kmr: '',
  description_en: '', description_ar: '', description_ckb: '', description_kmr: '',
  price_iqd: 0,
  active: true,
}

function PackageFields({
  value,
  onChange,
  slugEditable,
}: {
  value: Draft | Package
  onChange: (patch: Partial<Draft>) => void
  slugEditable: boolean
}) {
  const { t } = useI18n()
  return (
    <>
      <label className="field">
        <span className="muted">{t('marriageSubscriptions.slug')}</span>
        <input
          type="text"
          dir="ltr"
          value={value.slug}
          disabled={!slugEditable}
          onChange={(e) => onChange({ slug: e.target.value })}
        />
      </label>
      {LANGS.map(({ suf, labelKey, rtl }) => (
        <label className="field" key={`name_${suf}`}>
          <span className="muted">
            {t('marriageSubscriptions.name')} · {t(labelKey)}
          </span>
          <input
            type="text"
            dir={rtl ? 'rtl' : 'ltr'}
            value={(value as Draft)[`name_${suf}` as keyof Draft] as string}
            onChange={(e) => onChange({ [`name_${suf}`]: e.target.value } as Partial<Draft>)}
          />
        </label>
      ))}
      <label className="field">
        <span className="muted">{t('marriageSubscriptions.price')}</span>
        <input
          type="number"
          min={0}
          dir="ltr"
          value={value.price_iqd}
          onChange={(e) => onChange({ price_iqd: Number(e.target.value) })}
        />
      </label>
      {LANGS.map(({ suf, labelKey, rtl }) => (
        <label className="field" key={`description_${suf}`}>
          <span className="muted">
            {t('marriageSubscriptions.description')} · {t(labelKey)}
          </span>
          <textarea
            rows={2}
            dir={rtl ? 'rtl' : 'ltr'}
            value={(value as Draft)[`description_${suf}` as keyof Draft] as string}
            onChange={(e) => onChange({ [`description_${suf}`]: e.target.value } as Partial<Draft>)}
          />
        </label>
      ))}
    </>
  )
}

export default function MarriageSubscriptionsPage() {
  const { t } = useI18n()
  const toast = useToast()

  const [items, setItems] = useState<Package[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState<Draft>({ ...EMPTY_DRAFT })

  const [purchases, setPurchases] = useState<Purchase[]>([])
  const [purchasesLoading, setPurchasesLoading] = useState(true)
  const [busyPurchaseId, setBusyPurchaseId] = useState<number | null>(null)

  const load = () => {
    setLoading(true)
    api
      .get<{ items: Package[] }>('/api/admin/marriage/subscription-packages')
      .then((res) => { setItems(res.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  const loadPurchases = () => {
    setPurchasesLoading(true)
    api
      .get<{ items: Purchase[] }>('/api/admin/marriage/subscription-purchases?status=pending')
      .then((res) => setPurchases(res.data.items ?? []))
      .catch(() => setPurchases([]))
      .finally(() => setPurchasesLoading(false))
  }
  useEffect(() => { load(); loadPurchases() }, [])

  const patchItem = (id: number, patch: Partial<Package>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (p: Package) => {
    if (!p.name_en.trim()) {
      toast.error(t('marriageSubscriptions.need_name'))
      return
    }
    setSavingId(p.id)
    try {
      await api.patch(`/api/admin/marriage/subscription-packages/${p.id}`, {
        name_en: p.name_en, name_ar: p.name_ar, name_ckb: p.name_ckb, name_kmr: p.name_kmr,
        description_en: p.description_en, description_ar: p.description_ar,
        description_ckb: p.description_ckb, description_kmr: p.description_kmr,
        price_iqd: p.price_iqd, active: p.active,
      })
      toast.success(t('marriageSubscriptions.saved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!window.confirm(t('marriageSubscriptions.confirm_delete'))) return
    try {
      await api.delete(`/api/admin/marriage/subscription-packages/${id}`)
      toast.success(t('marriageSubscriptions.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.slug.trim() || !draft.name_en.trim()) {
      toast.error(t('marriageSubscriptions.need_name'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/marriage/subscription-packages', draft)
      toast.success(t('marriageSubscriptions.added'))
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
      await api.post('/api/admin/marriage/subscription-packages/reorder', {
        ids: reordered.map((x) => x.id),
      })
    } catch (e) {
      toast.error(describeError(e))
      load()
    }
  }

  const confirmPurchase = async (id: number) => {
    setBusyPurchaseId(id)
    try {
      await api.post(`/api/admin/marriage/subscription-purchases/${id}/confirm`, {})
      toast.success(t('marriageSubscriptions.purchase_confirmed'))
      loadPurchases()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyPurchaseId(null)
    }
  }

  const rejectPurchase = async (id: number) => {
    if (!window.confirm(t('marriageSubscriptions.confirm_reject'))) return
    setBusyPurchaseId(id)
    try {
      await api.post(`/api/admin/marriage/subscription-purchases/${id}/reject`, {})
      toast.success(t('marriageSubscriptions.purchase_rejected'))
      loadPurchases()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setBusyPurchaseId(null)
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('marriageSubscriptions.title')}</h1>
          <p className="muted">{t('marriageSubscriptions.subtitle')}</p>
        </div>
      </div>

      <h3 style={{ margin: '8px 0 0' }}>{t('marriageSubscriptions.section_pending')}</h3>
      <p className="muted" style={{ marginTop: 0 }}>{t('marriageSubscriptions.section_pending_desc')}</p>

      {purchasesLoading && <p className="muted">{t('common.loading')}</p>}
      {!purchasesLoading && purchases.length === 0 && (
        <p className="muted">{t('marriageSubscriptions.no_pending')}</p>
      )}
      {!purchasesLoading &&
        purchases.map((p) => (
          <div className="card" key={p.id}>
            <div className="page-head">
              <h3 style={{ margin: 0 }}>{p.package_name_en}</h3>
              <span className="badge tone-warning">{p.payment_method}</span>
            </div>
            <p className="muted">
              {t('marriageSubscriptions.purchase_user')}: #{p.user_id} · {t('marriageSubscriptions.purchase_price')}:{' '}
              {p.price_iqd.toLocaleString()} IQD · {new Date(p.created_at).toLocaleString()}
            </p>
            <div style={{ display: 'flex', gap: 8 }}>
              <button
                className="btn primary"
                onClick={() => confirmPurchase(p.id)}
                disabled={busyPurchaseId === p.id}
              >
                {t('marriageSubscriptions.confirm_purchase')}
              </button>
              <button
                className="btn danger"
                onClick={() => rejectPurchase(p.id)}
                disabled={busyPurchaseId === p.id}
              >
                {t('marriageSubscriptions.reject_purchase')}
              </button>
            </div>
          </div>
        ))}

      <h3 style={{ margin: '16px 0 0' }}>{t('marriageSubscriptions.section_packages')}</h3>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('marriageSubscriptions.add_new')}</h3>
        <PackageFields value={draft} onChange={(p) => setDraft((d) => ({ ...d, ...p }))} slugEditable />
        <button className="btn primary" onClick={addNew} disabled={adding}>
          {adding ? t('common.saving') : t('marriageSubscriptions.add_new')}
        </button>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading &&
        items.map((p, i) => (
          <div className="card" key={p.id}>
            <div className="page-head">
              <h3>{p.name_en || p.slug}</h3>
              <div style={{ display: 'flex', gap: 6 }}>
                <button className="btn" onClick={() => move(i, -1)} disabled={i === 0}>
                  ↑
                </button>
                <button className="btn" onClick={() => move(i, 1)} disabled={i === items.length - 1}>
                  ↓
                </button>
              </div>
            </div>
            <PackageFields
              value={p}
              onChange={(patch) => patchItem(p.id, patch)}
              slugEditable={false}
            />
            <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <input
                type="checkbox"
                checked={p.active}
                onChange={(e) => patchItem(p.id, { active: e.target.checked })}
              />
              <span className="muted">{t('marriageSubscriptions.active')}</span>
            </label>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn primary" onClick={() => save(p)} disabled={savingId === p.id}>
                {savingId === p.id ? t('common.saving') : t('common.save')}
              </button>
              <button className="btn danger" onClick={() => remove(p.id)}>
                {t('common.delete')}
              </button>
            </div>
          </div>
        ))}
    </div>
  )
}
