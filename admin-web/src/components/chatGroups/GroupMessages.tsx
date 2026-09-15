/**
 * GroupMessages — the staff view of ONE chat group's conversation (Phase 6b).
 *
 * WHAT IT RENDERS
 * Every message, oldest first, under the sender's REAL name. A member's
 * message also shows their masked label (masked groups) and role; a staff
 * message (sender_member_id 0) is marked Staff. Under the list, GroupComposer
 * or the reason there is none.
 *
 * POLLING
 * Like the other chat pages, every GROUP_POLL_INTERVAL_MS (3 s). The first
 * load reads the whole history; each poll asks only for messages after the
 * last id held, so a long group is not re-downloaded every 3 seconds. A poll
 * that fails keeps what is shown and says the list may be out of date.
 *
 * STATES: skeleton, the list, error with Try again, and an empty state.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import GroupComposer from './GroupComposer'
import { GROUP_POLL_INTERVAL_MS } from '../../lib/chatGroupDetail'
import { describeChatGroupError } from '../../lib/chatGroupErrors'
import {
  fetchAllGroupMessages,
  listGroupMessages,
  type ChatGroupDetail,
  type ChatGroupMember,
  type ChatGroupMessage,
} from '../../lib/chatGroupsApi'
import { formatDateTime } from '../../lib/dates'
import { useI18n, useStatusLabel } from '../../lib/i18n'

type Props = {
  group: ChatGroupDetail
  /** messages:add — shows the composer while the group is open. */
  canSend: boolean
}

type ListState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; items: ChatGroupMessage[] }

const SKELETON_ROWS = 3

export default function GroupMessages({ group, canSend }: Props) {
  const { t } = useI18n()
  const [list, setList] = useState<ListState>({ status: 'loading' })
  const [pollFailed, setPollFailed] = useState(false)
  const [reloadTick, setReloadTick] = useState(0)
  const itemsRef = useRef<ChatGroupMessage[] | null>(null)

  /** Appends whatever is newer than the last message held. */
  const fetchNewer = useCallback(async () => {
    const held = itemsRef.current
    if (!held) return
    try {
      const newer = await listGroupMessages(group.id, { afterId: held.at(-1)?.id ?? 0, limit: 100 })
      setPollFailed(false)
      if (newer.length === 0 || itemsRef.current !== held) return
      itemsRef.current = [...held, ...newer]
      setList({ status: 'ready', items: itemsRef.current })
    } catch (err) {
      // Not swallowed: the operator is told the list may be stale, and the
      // detail goes to the console for whoever debugs it.
      console.error('group messages: poll failed', err)
      setPollFailed(true)
    }
  }, [group.id])

  // First load, then the poll.
  useEffect(() => {
    let cancelled = false
    itemsRef.current = null
    fetchAllGroupMessages(group.id)
      .then((items) => {
        if (cancelled) return
        itemsRef.current = items
        setList({ status: 'ready', items })
      })
      .catch((err: unknown) => !cancelled && setList({ status: 'error', message: describeChatGroupError(err) }))
    const timer = setInterval(() => void fetchNewer(), GROUP_POLL_INTERVAL_MS)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [group.id, reloadTick, fetchNewer])

  function retry() {
    setList({ status: 'loading' })
    setReloadTick((n) => n + 1)
  }

  return (
    <section className="card stack" aria-labelledby={`messages-${group.id}`}>
      <strong id={`messages-${group.id}`}>{t('chat_groups.detail.messages_title')}</strong>
      <MessagesBody list={list} members={group.members} onRetry={retry} />
      {pollFailed && (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_groups.detail.poll_failed')}
        </p>
      )}
      {list.status !== 'error' && <GroupComposer group={group} canSend={canSend} onSent={fetchNewer} />}
    </section>
  )
}

// ─── The list ───

type BodyProps = { list: ListState; members: ChatGroupMember[]; onRetry: () => void }

function MessagesBody({ list, members, onRetry }: BodyProps) {
  const { t } = useI18n()
  if (list.status === 'loading') {
    return (
      <div className="stack" role="status" aria-busy="true" aria-label={t('chat_groups.detail.messages_loading')}>
        {Array.from({ length: SKELETON_ROWS }, (_, i) => (
          <span key={i} className="skeleton-line" aria-hidden="true" style={{ display: 'block', width: '70%', height: 14 }} />
        ))}
      </div>
    )
  }
  if (list.status === 'error') {
    return (
      <>
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {list.message}
        </p>
        <div>
          <button type="button" className="secondary" onClick={onRetry}>
            {t('error.retry')}
          </button>
        </div>
      </>
    )
  }
  if (list.items.length === 0) {
    return (
      <p className="muted" style={{ margin: 0 }}>
        {t('chat_groups.detail.messages_empty')}
      </p>
    )
  }
  const byId = new Map(members.map((m) => [m.id, m]))
  return (
    <ul
      className="stack"
      aria-label={t('chat_groups.detail.messages_aria')}
      style={{ listStyle: 'none', padding: 0, margin: 0, maxHeight: '28rem', overflowY: 'auto' }}
    >
      {list.items.map((message) => (
        <MessageRow key={message.id} message={message} member={byId.get(message.sender_member_id)} />
      ))}
    </ul>
  )
}

/** One message: real name, label · role (or Staff), time, body. */
function MessageRow({ message, member }: { message: ChatGroupMessage; member?: ChatGroupMember }) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const role = member ? statusLabel(member.role_in_group) : t('status.staff')
  const who = member?.masked && member.masked_label ? `${member.masked_label} · ${role}` : role

  return (
    <li className="stack" style={{ gap: 'var(--space-1)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <strong>{message.sender_name || t('common.user_ref', { id: message.sender_user_id })}</strong>
        <span className="muted">{who}</span>
        <time className="muted" dateTime={message.created_at} style={{ marginInlineStart: 'auto' }}>
          {formatDateTime(message.created_at)}
        </time>
      </div>
      <p style={{ margin: 0, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }} dir="auto">
        {message.body}
      </p>
    </li>
  )
}
