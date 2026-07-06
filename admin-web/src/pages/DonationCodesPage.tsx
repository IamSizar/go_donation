// DonationCodesPage — per-section transaction-code namespaces (#14) + per-section
// donation-arrived SMS alerts (#15). Lists the donation sections and lets an
// admin edit each section's code prefix, alert phone, and alert on/off.
// Loads GET /api/admin/donation-codes, saves via PUT /api/admin/donation-codes/:kind.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type SectionCode = {
  kind: string
  prefix: string
  next_seq: number
  notify_phone: string
  notify_enabled: boolean
  updated_at: string
}

type Draft = { prefix: string; phone: string; enabled: boolean }

const KIND_ORDER = ['general', 'campaign', 'sponsorship', 'in_kind', 'operational']
const PREFIX_RE = /^[A-Z0-9]{1,16}$/

const pad6 = (n: number) => String(n).padStart(6, '0')
const onlyDigits = (s: string) => s.replace(/[^0-9]/g, '')

export default function DonationCodesPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [codes, setCodes] = useState<SectionCode[]>([])
  const [drafts, setDrafts] = useState<Record<string, Draft>>({})
  const [loading, setLoading] = useState(true)
  const [savingKind, setSavingKind] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const load = () => {
    setLoading(true)
    api
      .get<{ codes: SectionCode[] }>('/api/admin/donation-codes')
      .then((res) => {
        const list = res.data.codes ?? []
        setCodes(list)
        setDrafts(
          Object.fromEntries(
            list.map((c) => [
              c.kind,
              { prefix: c.prefix, phone: c.notify_phone ?? '', enabled: !!c.notify_enabled },
            ]),
          ),
        )
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }

  useEffect(load, [])

  const kindLabel = (kind: string) => {
    const key = `donationCodes.kind_${kind}`
    const label = t(key)
    return label === key ? kind : label
  }

  const patch = (kind: string, p: Partial<Draft>) =>
    setDrafts((d) => ({ ...d, [kind]: { ...d[kind], ...p } }))

  const save = async (kind: string) => {
    const draft = drafts[kind]
    if (!draft) return
    const prefix = draft.prefix.trim().toUpperCase()
    if (!PREFIX_RE.test(prefix)) {
      toast.error(t('donationCodes.invalid_prefix'))
      return
    }
    const phone = onlyDigits(draft.phone)
    if (phone !== '' && (phone.length < 7 || phone.length > 20)) {
      toast.error(t('donationCodes.invalid_phone'))
      return
    }
    setSavingKind(kind)
    try {
      await api.put(`/api/admin/donation-codes/${kind}`, {
        prefix,
        notify_phone: phone,
        notify_enabled: draft.enabled,
      })
      toast.success(t('donationCodes.saved'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSavingKind(null)
    }
  }

  const ordered = [...codes].sort(
    (a, b) => KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind),
  )

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('donationCodes.title')}</h1>
          <p className="muted">{t('donationCodes.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading &&
        ordered.map((c) => {
          const draft = drafts[c.kind] ?? { prefix: '', phone: '', enabled: true }
          const preview = `${(draft.prefix || '—').toUpperCase()}-${pad6(c.next_seq)}`
          return (
            <div className="card" key={c.kind}>
              <h3>{kindLabel(c.kind)}</h3>
              <label className="field">
                <span className="muted">{t('donationCodes.prefix')}</span>
                <input
                  type="text"
                  dir="ltr"
                  maxLength={16}
                  value={draft.prefix}
                  onChange={(e) => patch(c.kind, { prefix: e.target.value.toUpperCase() })}
                />
              </label>
              <p className="muted">
                {t('donationCodes.next_number')}: <strong>{preview}</strong>
              </p>
              <label className="field">
                <span className="muted">{t('donationCodes.notify_phone')}</span>
                <input
                  type="text"
                  dir="ltr"
                  inputMode="numeric"
                  placeholder="9647xxxxxxxxx"
                  maxLength={20}
                  value={draft.phone}
                  onChange={(e) => patch(c.kind, { phone: onlyDigits(e.target.value) })}
                />
              </label>
              <label
                className="field"
                style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}
              >
                <input
                  type="checkbox"
                  checked={draft.enabled}
                  onChange={(e) => patch(c.kind, { enabled: e.target.checked })}
                />
                <span className="muted">{t('donationCodes.notify_enabled')}</span>
              </label>
              <button
                className="btn primary"
                onClick={() => save(c.kind)}
                disabled={savingKind === c.kind}
              >
                {savingKind === c.kind ? t('common.saving') : t('common.save')}
              </button>
            </div>
          )
        })}
    </div>
  )
}
