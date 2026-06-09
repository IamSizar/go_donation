// StatusCell — inline status editor for table rows.
//
// Renders a <select> with the current value + an allowed list. When the
// admin picks a new value:
//   1. updates the visible value optimistically
//   2. calls onSave(newValue) → Promise
//   3. on success, fires a toast; on failure, reverts and toasts the error
//
// Use anywhere you'd render a status badge but want it editable.

import { useEffect, useState } from 'react'
import { describeError } from '../lib/api'
import { useToast } from '../lib/toast'
import { useStatusLabel } from '../lib/i18n'

type Props = {
  value: string
  allowed: readonly string[] | string[]
  onSave: (next: string) => Promise<unknown>
  className?: string  // extra class for the wrapper (e.g. a colour class)
  disabled?: boolean
  label?: string      // for the toast message; defaults to "Status"
}

export default function StatusCell({ value, allowed, onSave, className, disabled, label = 'Status' }: Props) {
  const [val, setVal] = useState(value)
  const [busy, setBusy] = useState(false)
  const toast = useToast()
  const statusLabel = useStatusLabel()

  // Keep in sync if the parent passes a new value (e.g. after refetch).
  useEffect(() => { setVal(value) }, [value])

  async function change(next: string) {
    if (next === val || busy) return
    const prev = val
    setVal(next)  // optimistic
    setBusy(true)
    try {
      await onSave(next)
      toast.success(`${label} → ${statusLabel(next)}`)
    } catch (err) {
      setVal(prev)  // revert
      toast.error(describeError(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <select
      value={val}
      disabled={busy || disabled}
      onChange={(e) => change(e.target.value)}
      className={`status-cell ${className ?? ''}`}
      style={{ width: 'auto', minWidth: '120px' }}
    >
      {/* Make sure the current value is always present even if not in `allowed` */}
      {!allowed.includes(val) && <option value={val}>{statusLabel(val)}</option>}
      {allowed.map((s) => (
        <option key={s} value={s}>{statusLabel(s)}</option>
      ))}
    </select>
  )
}
