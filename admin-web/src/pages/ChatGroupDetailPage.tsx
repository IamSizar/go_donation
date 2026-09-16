/**
 * ChatGroupDetailPage — /chat-groups/:id: one chat group for staff (Phase 6b,
 * OPOS #26399).
 *
 * WHAT IT SHOWS (component tree)
 *   ChatGroupDetailPage          loads the group; owns it
 *   ├── GroupHeader              back link · kind · name · export · lifecycle
 *   ├── GroupMessages            polled conversation + GroupComposer
 *   ├── GroupRoster              members · remove · AddMemberForm
 *   └── GroupContactBlocks       refused contact-sharing attempts
 *
 * THE STATES
 *   loading    a skeleton shaped like the header and a panel
 *   forbidden  403 sensitive_data_required: a masked group needs sensitive
 *              data to read, so the operator is told what access is missing,
 *              not shown an error
 *   error      the translated reason (404 group_not_found included), Try
 *              again, and the way back
 *   ready      the panels; each has its own loading, error and empty states
 *
 * PERMISSIONS
 * The route needs messages:view. Lifecycle, add and remove need messages:edit;
 * the composer needs messages:add. After a change the group is fetched again
 * without the skeleton; if it is gone (moved to the Trash), the page returns
 * to the list.
 */
import { ShieldAlert } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import GroupContactBlocks from '../components/chatGroups/GroupContactBlocks'
import GroupHeader from '../components/chatGroups/GroupHeader'
import GroupMessages from '../components/chatGroups/GroupMessages'
import GroupRoster from '../components/chatGroups/GroupRoster'
import { useAuth } from '../lib/auth'
import { chatGroupErrorCode, describeChatGroupError } from '../lib/chatGroupErrors'
import { getGroup, type ChatGroupDetail } from '../lib/chatGroupsApi'
import { useI18n } from '../lib/i18n'
import { usePermission } from '../lib/permissions'

type PageState =
  | { status: 'loading' }
  | { status: 'forbidden' }
  | { status: 'error'; message: string }
  | { status: 'ready'; group: ChatGroupDetail }

/** The state a failed load leads to. */
function failureState(err: unknown): PageState {
  return chatGroupErrorCode(err) === 'sensitive_data_required'
    ? { status: 'forbidden' }
    : { status: 'error', message: describeChatGroupError(err) }
}

export default function ChatGroupDetailPage() {
  const { id } = useParams()
  const groupId = Number(id)
  const navigate = useNavigate()
  const { user } = useAuth()
  const canEdit = usePermission('messages', 'edit', user)
  const canSend = usePermission('messages', 'add', user)
  const [state, setState] = useState<PageState>({ status: 'loading' })
  const [reloadTick, setReloadTick] = useState(0)

  useEffect(() => {
    let cancelled = false
    getGroup(groupId)
      .then((group) => !cancelled && setState({ status: 'ready', group }))
      .catch((err: unknown) => !cancelled && setState(failureState(err)))
    return () => {
      cancelled = true
    }
  }, [groupId, reloadTick])

  const retry = useCallback(() => {
    setState({ status: 'loading' })
    setReloadTick((n) => n + 1)
  }, [])

  /** Fetches the group again in place; a group that is gone sends staff back to the list. */
  const refresh = useCallback(async () => {
    try {
      setState({ status: 'ready', group: await getGroup(groupId) })
    } catch (err) {
      if (chatGroupErrorCode(err) === 'group_not_found') navigate('/chat-groups')
      else setState(failureState(err))
    }
  }, [groupId, navigate])

  if (state.status === 'loading') return <DetailSkeleton />
  if (state.status === 'forbidden') return <SensitiveDataRequired />
  if (state.status === 'error') return <DetailError message={state.message} onRetry={retry} />

  const { group } = state
  return (
    <>
      <GroupHeader group={group} canEdit={canEdit} onLifecycleChanged={refresh} />
      <div className="stack">
        <GroupMessages group={group} canSend={canSend} />
        <GroupRoster group={group} canEdit={canEdit} onChanged={refresh} />
        <GroupContactBlocks groupId={group.id} />
      </div>
    </>
  )
}

// ─── States ───

function BackLink() {
  const { t } = useI18n()
  return (
    <p style={{ margin: 0 }}>
      <Link to="/chat-groups">{t('chat_groups.detail.back')}</Link>
    </p>
  )
}

/** A heading line over a panel of lines, as the page fills in. */
function DetailSkeleton() {
  const { t } = useI18n()
  return (
    <div className="stack" role="status" aria-busy="true" aria-label={t('chat_groups.detail.loading')}>
      <span className="skeleton-line" aria-hidden="true" style={{ display: 'block', width: '40%', height: 24 }} />
      <div className="card stack" aria-hidden="true">
        {[70, 55, 80].map((width) => (
          <span key={width} className="skeleton-line" style={{ display: 'block', width: `${width}%`, height: 14 }} />
        ))}
      </div>
    </div>
  )
}

/** 403 sensitive_data_required: what is missing and who can grant it. */
function SensitiveDataRequired() {
  const { t } = useI18n()
  return (
    <div className="stack">
      <BackLink />
      <div className="card stack" style={{ textAlign: 'center', paddingBlock: 'var(--space-7)' }}>
        <span aria-hidden="true" style={{ color: 'var(--muted)' }}>
          <ShieldAlert size={32} strokeWidth={1.8} />
        </span>
        <h1 style={{ margin: 0, fontSize: 'var(--text-lg)' }}>{t('chat_groups.detail.forbidden_title')}</h1>
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_groups.detail.forbidden_body')}
        </p>
      </div>
    </div>
  )
}

/** The reason the group failed to load, Try again, and the way back. */
function DetailError({ message, onRetry }: { message: string; onRetry: () => void }) {
  const { t } = useI18n()
  return (
    <div className="stack">
      <BackLink />
      <div className="card stack">
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {message}
        </p>
        <div>
          <button type="button" className="secondary" onClick={onRetry}>
            {t('error.retry')}
          </button>
        </div>
      </div>
    </div>
  )
}
