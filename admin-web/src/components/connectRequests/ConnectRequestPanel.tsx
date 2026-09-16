/**
 * ConnectRequestPanel — one connect request in full, and the way to decide it
 * (Phase 6c, OPOS #26400).
 *
 * WHAT IT SHOWS
 * Requester (their name when the server sent requester_name, else "Requester
 * #id"), what the request is about, when it was sent, the whole message and
 * the status. A declined request adds the reason the member was given; an
 * approved one links to its group at /chat-groups/:id (the 6b detail route).
 * target_hint is never shown (decision D8).
 *
 * STATES
 * loading (skeleton) → ready, or error (translated, with Try again; a request
 * that is gone reads as "no longer exists" via describeConnectRequestError).
 *
 * GATES
 * Approve and Decline appear only on a PENDING request, and only for staff
 * with messages:edit; others with a pending request are told why they cannot
 * decide it.
 *
 * AFTER A DECISION (OPOS #26493)
 * The panel stays on the request and shows its outcome straight from the
 * decision: Approved with the new group's link, or Declined with the reason
 * just given. It does not refetch the detail, so a refetch that fails or lags
 * cannot put the decision buttons back or replace the outcome with an error.
 * onDecided() lets the page refetch the list, where the row may drop out of
 * the current filter; choosing another row or filter moves on as usual.
 */
import { AnimatePresence } from 'framer-motion'
import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import ApproveRequestDialog from './ApproveRequestDialog'
import DeclineRequestDialog from './DeclineRequestDialog'
import { useAuth } from '../../lib/auth'
import { describeConnectRequestError } from '../../lib/chatGroupErrors'
import { getConnectRequest, type ConnectRequest } from '../../lib/chatGroupsApi'
import { requesterDisplayName, STATUS_TONE } from '../../lib/connectRequestForm'
import { formatDateTime } from '../../lib/dates'
import { useI18n, useStatusLabel } from '../../lib/i18n'
import { usePermission } from '../../lib/permissions'

type Props = {
  requestId: number
  /** Called after this request was approved or declined. */
  onDecided: () => void
}

type PanelState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; request: ConnectRequest }

export default function ConnectRequestPanel({ requestId, onDecided }: Props) {
  const { t } = useI18n()
  const [state, setState] = useState<PanelState>({ status: 'loading' })
  const [reloadTick, setReloadTick] = useState(0)
  const [dialog, setDialog] = useState<'approve' | 'decline' | null>(null)

  useEffect(() => {
    let cancelled = false
    getConnectRequest(requestId)
      .then(({ request, context_label }) => {
        if (!cancelled) setState({ status: 'ready', request: { ...request, context_label } })
      })
      .catch((err: unknown) => {
        if (!cancelled) setState({ status: 'error', message: describeConnectRequestError(err) })
      })
    return () => {
      cancelled = true
    }
  }, [requestId, reloadTick])

  const reload = useCallback(() => {
    setState({ status: 'loading' })
    setReloadTick((n) => n + 1)
  }, [])

  const closeDialog = useCallback(() => setDialog(null), [])

  /** Shows the decided request as the server now holds it, then tells the page. */
  const showDecision = useCallback(
    (decided: Pick<ConnectRequest, 'status' | 'group_id' | 'decline_reason'>) => {
      setDialog(null)
      setState((prev) => (prev.status === 'ready' ? { status: 'ready', request: { ...prev.request, ...decided } } : prev))
      onDecided()
    },
    [onDecided],
  )
  const handleApproved = useCallback((groupId: number) => showDecision({ status: 'approved', group_id: groupId }), [showDecision])
  const handleDeclined = useCallback((reason: string) => showDecision({ status: 'declined', decline_reason: reason }), [showDecision])

  return (
    <section className="card stack" aria-label={t('chat_groups.inbox.detail.aria')}>
      {state.status === 'loading' && (
        <div className="stack" role="status" aria-busy="true" aria-label={t('chat_groups.inbox.detail.loading')}>
          <span className="skeleton-line" style={{ display: 'block', width: '40%', height: 16 }} />
          <span className="skeleton-line" style={{ display: 'block', width: '90%', height: 12 }} />
          <span className="skeleton-line" style={{ display: 'block', width: '70%', height: 12 }} />
        </div>
      )}
      {state.status === 'error' && (
        <>
          <p className="error-box" role="alert" style={{ margin: 0 }}>
            {state.message}
          </p>
          <div>
            <button type="button" className="secondary" onClick={reload}>
              {t('error.retry')}
            </button>
          </div>
        </>
      )}
      {state.status === 'ready' && (
        <RequestDetail request={state.request} onApprove={() => setDialog('approve')} onDecline={() => setDialog('decline')} />
      )}

      <AnimatePresence>
        {state.status === 'ready' && dialog === 'approve' && (
          <ApproveRequestDialog key="approve" request={state.request} onClose={closeDialog} onApproved={handleApproved} />
        )}
        {state.status === 'ready' && dialog === 'decline' && (
          <DeclineRequestDialog key="decline" request={state.request} onClose={closeDialog} onDeclined={handleDeclined} />
        )}
      </AnimatePresence>
    </section>
  )
}

// ─── The request itself ───

type DetailProps = { request: ConnectRequest; onApprove: () => void; onDecline: () => void }

function RequestDetail({ request, onApprove, onDecline }: DetailProps) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const { user } = useAuth()
  const canEdit = usePermission('messages', 'edit', user)
  const isPending = request.status === 'pending'

  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <h2 style={{ margin: 0, fontSize: 'var(--text-lg)', overflowWrap: 'anywhere' }}>{requesterDisplayName(request, t)}</h2>
        <span className={`badge ${STATUS_TONE[request.status]}`}>{statusLabel(request.status)}</span>
      </div>
      <dl className="stack" style={{ margin: 0, gap: 'var(--space-2)' }}>
        <DetailItem term={t('chat_groups.inbox.detail.context')}>
          {t(`chat_groups.inbox.context_${request.context_type}`)} · {request.context_label}
        </DetailItem>
        <DetailItem term={t('chat_groups.inbox.detail.sent_at')}>
          <time dateTime={request.created_at}>{formatDateTime(request.created_at)}</time>
        </DetailItem>
        <DetailItem term={t('chat_groups.inbox.detail.message')}>
          <span style={{ whiteSpace: 'pre-wrap' }}>{request.message}</span>
        </DetailItem>
        {request.status === 'declined' && request.decline_reason && (
          <DetailItem term={t('chat_groups.inbox.detail.decline_reason')}>
            <span style={{ whiteSpace: 'pre-wrap' }}>{request.decline_reason}</span>
          </DetailItem>
        )}
      </dl>
      {request.status === 'approved' && request.group_id !== undefined && (
        <div>
          <Link to={`/chat-groups/${request.group_id}`}>
            {t('chat_groups.inbox.detail.open_group', { id: request.group_id })}
          </Link>
        </div>
      )}
      {isPending && canEdit && (
        <div className="row">
          <button type="button" onClick={onApprove}>
            {t('chat_groups.inbox.detail.approve')}
          </button>
          <button type="button" className="secondary" onClick={onDecline}>
            {t('chat_groups.inbox.detail.decline')}
          </button>
        </div>
      )}
      {isPending && !canEdit && (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_groups.inbox.detail.no_edit')}
        </p>
      )}
    </>
  )
}

function DetailItem({ term, children }: { term: string; children: ReactNode }) {
  return (
    <div>
      <dt className="form-label">{term}</dt>
      <dd style={{ margin: 0, overflowWrap: 'anywhere' }}>{children}</dd>
    </div>
  )
}
