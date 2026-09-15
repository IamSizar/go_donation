/**
 * ConnectRequestsPage — /chat-groups/connect-requests: the inbox of requests
 * members send to be put in touch about a donation or a case (Phase 6c,
 * OPOS #26400).
 *
 * WHAT IT SHOWS
 * A status filter (pending by default; GET …/connect-requests?status=), and
 * one row per request: requester, what it is about, a message preview, the
 * status and when it was sent. Choosing a row opens ConnectRequestPanel beside
 * the list, where a pending request can be approved or declined.
 *
 * THE FOUR STATES
 *   loading  a skeleton shaped like the rows
 *   content  the rows
 *   error    the translated reason and Try again (error.retry)
 *   empty    a designed message per filter
 *
 * PERMISSIONS
 * The route and the nav item need messages:view. Deciding needs messages:edit,
 * gated in the panel.
 */
import { Inbox } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import PageHead from '../components/PageHead'
import ConnectRequestPanel from '../components/connectRequests/ConnectRequestPanel'
import { describeConnectRequestError } from '../lib/chatGroupErrors'
import { listConnectRequests, type ConnectRequest, type ConnectRequestStatus } from '../lib/chatGroupsApi'
import { CONNECT_REQUEST_FILTERS, STATUS_TONE, requesterDisplayName } from '../lib/connectRequestForm'
import { formatDateTime } from '../lib/dates'
import { useI18n, useStatusLabel } from '../lib/i18n'

type ListState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; items: ConnectRequest[] }

const SKELETON_ROWS = 3
const PLAIN_LIST = { listStyle: 'none', padding: 0, margin: 0 } as const

export default function ConnectRequestsPage() {
  const { t } = useI18n()
  const [filter, setFilter] = useState<ConnectRequestStatus>('pending')
  const [list, setList] = useState<ListState>({ status: 'loading' })
  const [reloadTick, setReloadTick] = useState(0)
  const [selectedId, setSelectedId] = useState<number | null>(null)

  useEffect(() => {
    let cancelled = false
    listConnectRequests(filter)
      .then((items) => {
        if (!cancelled) setList({ status: 'ready', items })
      })
      .catch((err: unknown) => {
        if (!cancelled) setList({ status: 'error', message: describeConnectRequestError(err) })
      })
    return () => {
      cancelled = true
    }
  }, [filter, reloadTick])

  const reload = useCallback(() => {
    setList({ status: 'loading' })
    setReloadTick((n) => n + 1)
  }, [])

  function changeFilter(next: ConnectRequestStatus) {
    if (next === filter) return
    setList({ status: 'loading' })
    setSelectedId(null)
    setFilter(next)
  }

  return (
    <>
      <PageHead>
        <div>
          <h1>{t('chat_groups.inbox.title')}</h1>
          <p className="muted">{t('chat_groups.inbox.subtitle')}</p>
        </div>
      </PageHead>

      <StatusFilter value={filter} onChange={changeFilter} />

      <div
        style={{
          display: 'grid',
          gap: 'var(--space-4)',
          gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 22rem), 1fr))',
          alignItems: 'start',
        }}
      >
        <ListArea list={list} filter={filter} selectedId={selectedId} onSelect={setSelectedId} onRetry={reload} />
        {selectedId !== null && <ConnectRequestPanel key={selectedId} requestId={selectedId} onDecided={reload} />}
        {selectedId === null && list.status === 'ready' && list.items.length > 0 && (
          <p className="card muted" style={{ margin: 0 }}>
            {t('chat_groups.inbox.detail.choose')}
          </p>
        )}
      </div>
    </>
  )
}

// ─── The filter ───

function StatusFilter({ value, onChange }: { value: ConnectRequestStatus; onChange: (s: ConnectRequestStatus) => void }) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  return (
    <div className="row" role="group" aria-label={t('chat_groups.inbox.filter_aria')} style={{ marginBlockEnd: 'var(--space-4)' }}>
      {CONNECT_REQUEST_FILTERS.map((status) => (
        <button
          key={status}
          type="button"
          className={status === value ? undefined : 'secondary'}
          aria-pressed={status === value}
          onClick={() => onChange(status)}
        >
          {statusLabel(status)}
        </button>
      ))}
    </div>
  )
}

// ─── The list area: one of the four states ───

type ListAreaProps = {
  list: ListState
  filter: ConnectRequestStatus
  selectedId: number | null
  onSelect: (id: number) => void
  onRetry: () => void
}

function ListArea({ list, filter, selectedId, onSelect, onRetry }: ListAreaProps) {
  const { t } = useI18n()
  if (list.status === 'loading') return <ListSkeleton />
  if (list.status === 'error') {
    return (
      <div className="card stack">
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {list.message}
        </p>
        <div>
          <button type="button" className="secondary" onClick={onRetry}>
            {t('error.retry')}
          </button>
        </div>
      </div>
    )
  }
  if (list.items.length === 0) return <EmptyState filter={filter} />
  return (
    <div className="card">
      <ul className="stack" aria-label={t('chat_groups.inbox.list_aria')} style={PLAIN_LIST}>
        {list.items.map((request) => (
          <li key={request.id}>
            <RequestRow request={request} isSelected={request.id === selectedId} onSelect={onSelect} />
          </li>
        ))}
      </ul>
    </div>
  )
}

function ListSkeleton() {
  const { t } = useI18n()
  return (
    <div className="card stack" role="status" aria-busy="true" aria-label={t('chat_groups.inbox.loading')}>
      {Array.from({ length: SKELETON_ROWS }, (_, i) => (
        <div key={i} className="stack" aria-hidden="true">
          <span className="skeleton-line" style={{ display: 'block', width: '35%', height: 14 }} />
          <span className="skeleton-line" style={{ display: 'block', width: '75%', height: 12 }} />
        </div>
      ))}
    </div>
  )
}

function EmptyState({ filter }: { filter: ConnectRequestStatus }) {
  const { t } = useI18n()
  return (
    <div className="card stack" style={{ textAlign: 'center', paddingBlock: 'var(--space-7)' }}>
      <span aria-hidden="true" style={{ color: 'var(--muted)' }}>
        <Inbox size={32} strokeWidth={1.8} />
      </span>
      <h2 style={{ margin: 0, fontSize: 'var(--text-lg)' }}>{t(`chat_groups.inbox.empty.${filter}_title`)}</h2>
      <p className="muted" style={{ margin: 0 }}>
        {t(`chat_groups.inbox.empty.${filter}_body`)}
      </p>
    </div>
  )
}

type RowProps = { request: ConnectRequest; isSelected: boolean; onSelect: (id: number) => void }

/** One request, as a button that opens it in the panel. */
function RequestRow({ request, isSelected, onSelect }: RowProps) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  return (
    <button
      type="button"
      className="secondary stack"
      aria-pressed={isSelected}
      onClick={() => onSelect(request.id)}
      style={{ width: '100%', textAlign: 'start', gap: 'var(--space-1)', alignItems: 'stretch' }}
    >
      <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <span className={`badge ${STATUS_TONE[request.status]}`}>{statusLabel(request.status)}</span>
        <strong style={{ overflowWrap: 'anywhere' }}>{requesterDisplayName(request, t)}</strong>
        <time className="muted" dateTime={request.created_at} style={{ marginInlineStart: 'auto' }}>
          {formatDateTime(request.created_at)}
        </time>
      </span>
      <span className="muted" style={{ overflowWrap: 'anywhere' }}>
        {t(`chat_groups.inbox.context_${request.context_type}`)} · <span>{request.context_label}</span>
      </span>
      <span
        style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'block' }}
      >
        {request.message}
      </span>
    </button>
  )
}
