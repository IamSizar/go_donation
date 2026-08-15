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
import { useI18n, useStatusLabel } from '../lib/i18n'
import EditModal, { type FieldSpec } from './EditModal'

// The reason box. One required textarea, reusing field.review_notes' label,
// which already exists in all four locales.
const REASON_FIELDS: FieldSpec[] = [
  { key: 'reason', label: 'Reason', labelKey: 'field.review_notes', type: 'textarea', rows: 4, required: true },
]

type Props = {
  value: string
  allowed: readonly string[] | string[]
  // `reason` is present only for a status listed in `reasonRequiredFor`.
  // Callers that ask for no reason keep their existing one-argument handler.
  onSave: (next: string, reason?: string) => Promise<unknown>
  // Statuses that must not be applied until the reviewer says WHY. Picking one
  // opens a required reason box; cancelling leaves the status untouched.
  //
  // Opt-in per column: a bare state flip ("published", "paused") needs no
  // justification, but refusing someone's aid case does — the applicant is
  // shown the decision in the app, and "rejected" on its own is not an answer.
  reasonRequiredFor?: readonly string[]
  className?: string  // extra class for the wrapper (e.g. a colour class)
  disabled?: boolean
  label?: string      // for the toast message; defaults to "Status"
  // Note #13 — per-column display-label overrides, keyed by raw value. The
  // `status.*` i18n namespace is shared across every StatusCell in the app
  // (e.g. 'paused' also backs Marriage and Sponsorships, where it genuinely
  // means "on hold"), so a column that needs a DIFFERENT label for the same
  // raw value — without touching what it means elsewhere — passes it here
  // instead of adding a second global status key that would collide.
  labelOverrides?: Record<string, string>
}

export default function StatusCell({ value, allowed, onSave, reasonRequiredFor, className, disabled, label = 'Status', labelOverrides }: Props) {
  const [val, setVal] = useState(value)
  const [busy, setBusy] = useState(false)
  // The status waiting on a reason. Null when no reason box is open.
  const [awaitingReason, setAwaitingReason] = useState<string | null>(null)
  const toast = useToast()
  const { t } = useI18n()
  const globalStatusLabel = useStatusLabel()
  const statusLabel = (v: string) => labelOverrides?.[v] ?? globalStatusLabel(v)

  // Keep in sync if the parent passes a new value (e.g. after refetch).
  useEffect(() => { setVal(value) }, [value])

  async function change(next: string) {
    if (next === val || busy) return
    if (reasonRequiredFor?.includes(next)) {
      // Ask first, save after. The visible value is deliberately NOT updated
      // yet: an optimistic flip here would show the case as rejected while the
      // operator is still deciding, and stay wrong if they cancel.
      setAwaitingReason(next)
      return
    }
    await commit(next)
  }

  async function commit(next: string, reason?: string) {
    const prev = val
    setVal(next)  // optimistic
    setBusy(true)
    try {
      await onSave(next, reason)
      toast.success(`${label} → ${statusLabel(next)}`)
    } catch (err) {
      setVal(prev)  // revert
      toast.error(describeError(err))
      throw err     // let the modal keep itself open and show the failure
    } finally {
      setBusy(false)
    }
  }

  // Note #2 — this used to be a flat 150px for every StatusCell everywhere,
  // regardless of whether its options were "YES"/"NO" or a long role name.
  // Tables stacking several of these (e.g. Users: role/active/admin/tier/
  // account_status) paid for the longest possible column five times over,
  // pushing later columns off-screen. Size to the WIDEST option actually in
  // `allowed` (not the current value) so the box still never resizes when
  // the selection changes — same layout-stability guarantee as before, just
  // sized per-column instead of one-size-fits-all.
  const longest = Math.max(
    statusLabel(val).length,
    ...(allowed.length ? allowed.map((s) => statusLabel(s).length) : [0]),
  )
  const computedWidth = Math.max(80, Math.min(150, longest * 8 + 44))

  return (
    <>
      <select
        value={val}
        disabled={busy || disabled}
        onChange={(e) => change(e.target.value)}
        className={`status-cell ${className ?? ''}`}
        /* Fixed width (not auto) so the cell doesn't resize — and the column
           doesn't shift — when the selected option's text length changes. Long
           labels are clipped with an ellipsis by .status-cell; the dropdown still
           shows each option in full when opened. (Volunteers §13B layout fix.) */
        style={{ width: `${computedWidth}px` }}
      >
        {/* Make sure the current value is always present even if not in `allowed` */}
        {!allowed.includes(val) && <option value={val}>{statusLabel(val)}</option>}
        {allowed.map((s) => (
          <option key={s} value={s}>{statusLabel(s)}</option>
        ))}
      </select>
      {/* EditModal already owns required-field validation, Esc/click-outside,
          in-flight disabling and inline error display, so the reason box gets
          all of that instead of a second hand-rolled dialog. */}
      <EditModal
        open={awaitingReason !== null}
        mode="create"
        title={t('common.reason_title', { status: statusLabel(awaitingReason ?? '') })}
        initial={{}}
        fields={REASON_FIELDS}
        saveLabel={t('common.confirm')}
        onSave={(data) => commit(awaitingReason!, String(data.reason ?? ''))}
        onClose={() => setAwaitingReason(null)}
      />
    </>
  )
}
