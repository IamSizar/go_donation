/**
 * GroupContactBlocks — the refused contact-sharing attempts in ONE chat group
 * (Phase 6b, OPOS #26399).
 *
 * WHY NOT ContactBlocksPanel
 * That panel reads /api/admin/chats/:id/contact-blocks and a `thread_id`; a
 * group's log is /api/admin/chat-groups/:id/contact-blocks with a `group_id`,
 * and its refusals carry chat-group codes. This keeps the panel's look and its
 * `contact_blocks.*` strings, and reads the group route instead.
 *
 * Bodies are redacted when they are captured, so printing them in full cannot
 * leak a number. Loaded once, not polled: it is a record to review.
 *
 * STATES: loading line, the list, an error with Try again, and "nothing was
 * blocked" (the good outcome, so it must not read like a fault).
 */
import { useEffect, useState } from 'react'
import { describeChatGroupError } from '../../lib/chatGroupErrors'
import { listGroupContactBlocks, type ChatGroupContactBlock } from '../../lib/chatGroupsApi'
import { formatDateTime } from '../../lib/dates'
import { useI18n } from '../../lib/i18n'

/** `both` is the stronger signal: the sender reached for two channels at once. */
const KIND_TONE: Record<ChatGroupContactBlock['kind'], string> = {
  phone: 'tone-warning',
  email: 'tone-warning',
  both: 'tone-danger',
}

type BlocksState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; items: ChatGroupContactBlock[] }

export default function GroupContactBlocks({ groupId }: { groupId: number }) {
  const { t } = useI18n()
  const [state, setState] = useState<BlocksState>({ status: 'loading' })
  const [reloadTick, setReloadTick] = useState(0)
  const headingId = `group-blocks-${groupId}`

  // State is set only once the request settles, never synchronously here.
  useEffect(() => {
    let cancelled = false
    listGroupContactBlocks(groupId)
      .then((items) => !cancelled && setState({ status: 'ready', items }))
      .catch((err: unknown) => !cancelled && setState({ status: 'error', message: describeChatGroupError(err) }))
    return () => {
      cancelled = true
    }
  }, [groupId, reloadTick])

  function retry() {
    setState({ status: 'loading' })
    setReloadTick((n) => n + 1)
  }

  return (
    <section className="card stack" aria-labelledby={headingId}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <strong id={headingId}>{t('contact_blocks.title')}</strong>
        {state.status === 'ready' && state.items.length > 0 && (
          <span className="badge tone-warning">{t('contact_blocks.count', { count: state.items.length })}</span>
        )}
      </div>
      <BlocksBody state={state} onRetry={retry} />
    </section>
  )
}

/** One of the four states. */
function BlocksBody({ state, onRetry }: { state: BlocksState; onRetry: () => void }) {
  const { t } = useI18n()
  if (state.status === 'loading') return <p className="muted">{t('contact_blocks.loading')}</p>
  if (state.status === 'error') {
    return (
      <>
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {state.message}
        </p>
        <div>
          <button type="button" className="secondary" onClick={onRetry}>
            {t('error.retry')}
          </button>
        </div>
      </>
    )
  }
  if (state.items.length === 0) return <p className="muted">{t('contact_blocks.none')}</p>
  return (
    <>
      <p className="muted">{t('contact_blocks.explain')}</p>
      <ul className="stack" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
        {state.items.map((block) => (
          <BlockRow key={block.id} block={block} />
        ))}
      </ul>
    </>
  )
}

/** One refusal: who, what kind, when, and the redacted text. */
function BlockRow({ block }: { block: ChatGroupContactBlock }) {
  const { t } = useI18n()
  return (
    <li className="stack" style={{ gap: 'var(--space-1)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <strong>{block.sender_name || t('common.user_ref', { id: block.sender_user_id })}</strong>
        <span className={`badge ${KIND_TONE[block.kind]}`}>{t(`contact_blocks.kind_${block.kind}`)}</span>
        <time className="muted" dateTime={block.created_at}>
          {formatDateTime(block.created_at)}
        </time>
      </div>
      <p className="muted" style={{ margin: 0, overflowWrap: 'anywhere' }}>
        {block.redacted_body}
      </p>
    </li>
  )
}
