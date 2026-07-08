import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useToast } from '../lib/toast'
import { useI18n } from '../lib/i18n'

// A single labeled number setting: loads from `getUrl`, saves to `putUrl`.
function SettingRow({
  title,
  desc,
  placeholder,
  getUrl,
  putUrl,
  savedMsg,
}: {
  title: string
  desc: string
  placeholder: string
  getUrl: string
  putUrl: string
  savedMsg: string
}) {
  const toast = useToast()
  const [value, setValue] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const { t } = useI18n()

  useEffect(() => {
    let cancelled = false
    api
      .get(getUrl)
      .then(({ data }) => {
        if (!cancelled) setValue(String(data?.number ?? ''))
      })
      .catch(() => {})
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [getUrl])

  const save = async () => {
    setSaving(true)
    try {
      const { data } = await api.put(putUrl, { number: value })
      setValue(String(data?.number ?? ''))
      toast.success(savedMsg)
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div style={{ marginBottom: 16 }}>
      <div style={{ fontWeight: 700, marginBottom: 4 }}>{title}</div>
      <div style={{ fontSize: 13, opacity: 0.7, marginBottom: 10 }}>{desc}</div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        <input
          type="tel"
          inputMode="numeric"
          value={value}
          disabled={loading}
          placeholder={placeholder}
          onChange={(e) => setValue(e.target.value)}
          style={{ flex: '1 1 240px', minWidth: 200 }}
        />
        <button className="btn" onClick={save} disabled={saving || loading}>
          {saving ? '…' : t('support_wa.save')}
        </button>
      </div>
    </div>
  )
}

// #36 — admin-editable support WhatsApp number + FIB account number, co-located
// on the Support page. WhatsApp is offered in the AI chat after 3 messages; the
// FIB number is the same one shown on the donate screen (payment method).
export default function SupportWhatsappCard() {
  const { t } = useI18n()
  return (
    <div className="card" style={{ padding: 16 }}>
      <SettingRow
        title={t('support_wa.title')}
        desc={t('support_wa.desc')}
        placeholder="9647501234567"
        getUrl="/api/admin/settings/support-whatsapp"
        putUrl="/api/admin/settings/support-whatsapp"
        savedMsg={t('support_wa.saved')}
      />
      <div style={{ borderTop: '1px solid rgba(128,128,128,0.2)', paddingTop: 14 }}>
        <SettingRow
          title={t('support_wa.fib_title')}
          desc={t('support_wa.fib_desc')}
          placeholder="7510208962"
          getUrl="/api/admin/settings/fib-number"
          putUrl="/api/admin/settings/fib-number"
          savedMsg={t('support_wa.fib_saved')}
        />
      </div>
    </div>
  )
}
