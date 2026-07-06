// PaymentMethodsPage — admin CMS for the donation payment methods the app shows
// on the donate screen (#19). Add / edit (4 languages + account details + type)
// / toggle active / reorder / delete. GET/POST/PATCH/reorder/DELETE
// /api/admin/payment-methods.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Method = {
  id: number
  slug: string
  method_type: string
  name_en: string
  name_ar: string
  name_ckb: string
  name_kmr: string
  instructions_en: string
  instructions_ar: string
  instructions_ckb: string
  instructions_kmr: string
  account_number: string
  account_name: string
  display_order: number
  active: boolean
}

type Draft = Omit<Method, 'id' | 'slug' | 'display_order' | 'active'>

const METHOD_TYPES = ['cash', 'bank', 'wallet']
const LANGS: Array<{ suf: 'en' | 'ar' | 'ckb' | 'kmr'; labelKey: string; rtl: boolean }> = [
  { suf: 'en', labelKey: 'common.lang_en', rtl: false },
  { suf: 'ar', labelKey: 'common.lang_ar', rtl: true },
  { suf: 'ckb', labelKey: 'common.lang_sorani', rtl: true },
  { suf: 'kmr', labelKey: 'common.lang_badini', rtl: true },
]

const EMPTY_DRAFT: Draft = {
  method_type: 'bank',
  name_en: '', name_ar: '', name_ckb: '', name_kmr: '',
  instructions_en: '', instructions_ar: '', instructions_ckb: '', instructions_kmr: '',
  account_number: '', account_name: '',
}

function MethodFields({
  value,
  onChange,
}: {
  value: Draft | Method
  onChange: (patch: Partial<Draft>) => void
}) {
  const { t } = useI18n()
  return (
    <>
      <label className="field">
        <span className="muted">{t('paymentMethods.method_type')}</span>
        <select
          value={value.method_type}
          onChange={(e) => onChange({ method_type: e.target.value })}
        >
          {METHOD_TYPES.map((mt) => (
            <option key={mt} value={mt}>
              {mt}
            </option>
          ))}
        </select>
      </label>
      {LANGS.map(({ suf, labelKey, rtl }) => (
        <label className="field" key={`name_${suf}`}>
          <span className="muted">
            {t('paymentMethods.name')} · {t(labelKey)}
          </span>
          <input
            type="text"
            dir={rtl ? 'rtl' : 'ltr'}
            value={(value as Draft)[`name_${suf}` as keyof Draft]}
            onChange={(e) =>
              onChange({ [`name_${suf}`]: e.target.value } as Partial<Draft>)
            }
          />
        </label>
      ))}
      <label className="field">
        <span className="muted">{t('paymentMethods.account_number')}</span>
        <input
          type="text"
          dir="ltr"
          value={value.account_number}
          onChange={(e) => onChange({ account_number: e.target.value })}
        />
      </label>
      <label className="field">
        <span className="muted">{t('paymentMethods.account_name')}</span>
        <input
          type="text"
          value={value.account_name}
          onChange={(e) => onChange({ account_name: e.target.value })}
        />
      </label>
      {LANGS.map(({ suf, labelKey, rtl }) => (
        <label className="field" key={`instructions_${suf}`}>
          <span className="muted">
            {t('paymentMethods.instructions')} · {t(labelKey)}
          </span>
          <textarea
            rows={2}
            dir={rtl ? 'rtl' : 'ltr'}
            value={(value as Draft)[`instructions_${suf}` as keyof Draft]}
            onChange={(e) =>
              onChange({ [`instructions_${suf}`]: e.target.value } as Partial<Draft>)
            }
          />
        </label>
      ))}
    </>
  )
}

export default function PaymentMethodsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Method[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [adding, setAdding] = useState(false)
  const [draft, setDraft] = useState<Draft>({ ...EMPTY_DRAFT })

  const load = () => {
    setLoading(true)
    api
      .get<{ items: Method[] }>('/api/admin/payment-methods')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const patchItem = (id: number, patch: Partial<Method>) =>
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...patch } : x)))

  const save = async (m: Method) => {
    if (!m.name_en.trim()) {
      toast.error(t('paymentMethods.need_en'))
      return
    }
    setSavingId(m.id)
    try {
      await api.patch(`/api/admin/payment-methods/${m.id}`, {
        method_type: m.method_type,
        name_en: m.name_en, name_ar: m.name_ar, name_ckb: m.name_ckb, name_kmr: m.name_kmr,
        instructions_en: m.instructions_en, instructions_ar: m.instructions_ar,
        instructions_ckb: m.instructions_ckb, instructions_kmr: m.instructions_kmr,
        account_number: m.account_number, account_name: m.account_name, active: m.active,
      })
      toast.success(t('paymentMethods.saved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingId(null)
    }
  }

  const remove = async (id: number) => {
    if (!window.confirm(t('paymentMethods.confirm_delete'))) return
    try {
      await api.delete(`/api/admin/payment-methods/${id}`)
      toast.success(t('paymentMethods.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const addNew = async () => {
    if (!draft.name_en.trim()) {
      toast.error(t('paymentMethods.need_en'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/payment-methods', draft)
      toast.success(t('paymentMethods.added'))
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
      await api.post('/api/admin/payment-methods/reorder', {
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
          <h1>{t('paymentMethods.title')}</h1>
          <p className="muted">{t('paymentMethods.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('paymentMethods.add_new')}</h3>
        <MethodFields value={draft} onChange={(p) => setDraft((d) => ({ ...d, ...p }))} />
        <button className="btn primary" onClick={addNew} disabled={adding}>
          {adding ? t('common.saving') : t('paymentMethods.add_new')}
        </button>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading &&
        items.map((m, i) => (
          <div className="card" key={m.id}>
            <div className="page-head">
              <h3>{m.name_en || m.slug}</h3>
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
            <MethodFields value={m} onChange={(p) => patchItem(m.id, p)} />
            <label
              className="field"
              style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}
            >
              <input
                type="checkbox"
                checked={m.active}
                onChange={(e) => patchItem(m.id, { active: e.target.checked })}
              />
              <span className="muted">{t('paymentMethods.active')}</span>
            </label>
            <div style={{ display: 'flex', gap: 8 }}>
              <button
                className="btn primary"
                onClick={() => save(m)}
                disabled={savingId === m.id}
              >
                {savingId === m.id ? t('common.saving') : t('common.save')}
              </button>
              <button className="btn danger" onClick={() => remove(m.id)}>
                {t('common.delete')}
              </button>
            </div>
          </div>
        ))}
    </div>
  )
}
