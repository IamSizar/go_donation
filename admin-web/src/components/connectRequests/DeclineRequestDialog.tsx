/**
 * DeclineRequestDialog — declines a pending connect request with a reason
 * (Phase 6c, OPOS #26400).
 *
 * The reason is shown to the member in the app, and the dialog says so beside
 * the field. It is required after trimming and capped at
 * DECLINE_REASON_MAX_LENGTH (lib/connectRequestForm.ts). Decline request stays
 * disabled while the reason breaks a rule; the rule itself is named once the
 * field has been touched.
 *
 * On success: a toast, then onDeclined(reason) with the trimmed reason sent. A refusal
 * (409 connect_request_decided, the 404 for a request that is gone) is
 * translated by describeConnectRequestError and shown atop the form; the
 * typed reason is kept.
 */
import { useId, useState, type FormEvent } from 'react'
import DialogFrame from './DialogFrame'
import FieldNote from '../chatGroups/FieldNote'
import { describeConnectRequestError } from '../../lib/chatGroupErrors'
import { declineConnectRequest, type ConnectRequest } from '../../lib/chatGroupsApi'
import { DECLINE_REASON_MAX_LENGTH, validateDeclineReason } from '../../lib/connectRequestForm'
import { useI18n } from '../../lib/i18n'
import { useToast } from '../../lib/toast'

type Props = {
  request: ConnectRequest
  onClose: () => void
  /** Called after the server recorded the decline, with the reason it was sent. */
  onDeclined: (reason: string) => void
}

export default function DeclineRequestDialog({ request, onClose, onDeclined }: Props) {
  const { t } = useI18n()
  const toast = useToast()
  const id = useId()
  const [reason, setReason] = useState('')
  const [touched, setTouched] = useState(false)
  const [busy, setBusy] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const issue = validateDeclineReason(reason)
  const hintId = `${id}-hint`
  const errorId = `${id}-error`

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (issue || busy) return
    setBusy(true)
    setSubmitError(null)
    try {
      const sentReason = reason.trim()
      await declineConnectRequest(request.id, sentReason)
      toast.success(t('chat_groups.inbox.decline.declined_toast'))
      onDeclined(sentReason)
    } catch (err) {
      setSubmitError(describeConnectRequestError(err))
      setBusy(false)
    }
  }

  const footer = (
    <>
      <button type="button" className="secondary" onClick={onClose} disabled={busy}>
        {t('common.cancel')}
      </button>
      <button type="submit" className="danger" disabled={Boolean(issue) || busy} aria-busy={busy || undefined}>
        {busy ? t('chat_groups.inbox.decline.submitting') : t('chat_groups.inbox.decline.submit')}
      </button>
    </>
  )

  return (
    <DialogFrame
      title={t('chat_groups.inbox.decline.title')}
      busy={busy}
      onClose={onClose}
      onSubmit={submit}
      width="min(560px, 94vw)"
      footer={footer}
    >
      {submitError && (
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {submitError}
        </p>
      )}
      <p className="muted" style={{ margin: 0 }}>
        {t('chat_groups.inbox.decline.intro')}
      </p>
      <div className="form-row field">
        <label className="form-label" htmlFor={id}>
          {t('chat_groups.inbox.decline.reason_label')}
        </label>
        <textarea
          id={id}
          rows={4}
          dir="auto"
          value={reason}
          disabled={busy}
          aria-invalid={touched && issue ? true : undefined}
          aria-describedby={touched && issue ? `${hintId} ${errorId}` : hintId}
          onChange={(e) => {
            setReason(e.target.value)
            setSubmitError(null)
          }}
          onBlur={() => setTouched(true)}
        />
        <span id={hintId} className="form-hint">
          {t('chat_groups.inbox.decline.reason_hint', { max: DECLINE_REASON_MAX_LENGTH })}
        </span>
        <FieldNote id={errorId} issue={touched ? issue : undefined} />
      </div>
    </DialogFrame>
  )
}
