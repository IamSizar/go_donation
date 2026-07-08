// FieldRulesPage — admin sets which optional registration fields are required
// (#43). Loads GET /api/admin/registration/field-rules and toggles each via
// POST /api/admin/registration/field-rules/:key.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Rule = { field_key: string; required: boolean; display_order: number }

// Humanize a field_key for display (admin-facing).
const humanize = (k: string) =>
  k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())

export default function FieldRulesPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Rule[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingKey, setSavingKey] = useState<string | null>(null)

  const load = () => {
    setLoading(true)
    api
      .get<{ items: Rule[] }>('/api/admin/registration/field-rules')
      .then((res) => { setItems(res.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const toggle = async (r: Rule, required: boolean) => {
    setItems((xs) => xs.map((x) => (x.field_key === r.field_key ? { ...x, required } : x)))
    setSavingKey(r.field_key)
    try {
      await api.post(`/api/admin/registration/field-rules/${r.field_key}`, { required })
      toast.success(t('fieldRules.saved'))
    } catch (e) {
      toast.error(describeError(e))
      load()
    } finally {
      setSavingKey(null)
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('fieldRules.title')}</h1>
          <p className="muted">{t('fieldRules.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && items.map((r) => (
        <div className="card" key={r.field_key}>
          <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            <input
              type="checkbox"
              checked={r.required}
              disabled={savingKey === r.field_key}
              onChange={(e) => toggle(r, e.target.checked)}
            />
            <span><strong>{humanize(r.field_key)}</strong> — {t('fieldRules.required')}</span>
          </label>
        </div>
      ))}
    </div>
  )
}
