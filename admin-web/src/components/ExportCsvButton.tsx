import { useState } from 'react'
import { api, canExportData } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Props = {
  /** Runs the page's actual CSV build/download once the PIN is confirmed. */
  onExport: () => void
  /** Optional label override; defaults to the shared "Export CSV" string. */
  label?: string
  /** Optional button class; defaults to the neutral "secondary" style. */
  className?: string
}

// ExportCsvButton is the single, shared entry point for every CSV export in the
// dashboard (Phase 7 · G-07). It enforces two things the loose per-page buttons
// couldn't:
//   1. Tier gate — only admin-level staff even see the button; lower tiers get
//      nothing rendered (canExportData).
//   2. PIN step-up — clicking asks for the admin's own password, verified
//      server-side, before the export runs.
export default function ExportCsvButton({ onExport, label, className }: Props) {
  const { user } = useAuth()
  const { t } = useI18n()
  const toast = useToast()
  const [busy, setBusy] = useState(false)

  // Hidden entirely for non-authorized tiers — the backend enforces the same.
  if (!canExportData(user)) return null

  async function handleClick() {
    if (busy) return
    const pin = window.prompt(t('export.pin_prompt'))
    if (pin == null) return // user cancelled the prompt
    if (!pin.trim()) {
      toast.error(t('export.pin_required'))
      return
    }
    setBusy(true)
    try {
      const { data } = await api.post('/api/admin/verify-password', { password: pin })
      if (data?.ok) {
        onExport()
      } else {
        toast.error(data?.error || t('export.pin_incorrect'))
      }
    } catch {
      toast.error(t('export.pin_incorrect'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <button
      className={className ?? 'secondary'}
      onClick={handleClick}
      disabled={busy}
    >
      {label ?? t('common.export_csv')}
    </button>
  )
}
