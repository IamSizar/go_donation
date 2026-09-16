/**
 * ChatGroupsPage — /chat-groups: every staff-supervised chat group, and the
 * way in to creating one (Phase 6a, OPOS #26398).
 *
 * WHAT IT SHOWS
 * One row per group from GET /api/admin/chat-groups: a kind badge (masked or
 * team), the group's name, its last message and when that was. A masked
 * group has no title of its own (members only ever see labels), so it is
 * named by its id.
 *
 * THE FOUR STATES
 *   loading  a skeleton shaped like the rows, so the list fills in
 *   content  the rows
 *   error    the translated reason and a Try again button
 *   empty    what a chat group is for, and a Create call to action
 *
 * PERMISSIONS
 * The route needs messages:view (the nav item is gated on the same module).
 * Both Create buttons need messages:add; staff without it are told who can
 * create a group instead of being offered a button the server would refuse.
 *
 * Each row's name links to the group's detail page (Phase 6b, /chat-groups/:id).
 */
import { AnimatePresence } from 'framer-motion'
import { Users } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import PageHead from '../components/PageHead'
import DateCell from '../components/DateCell'
import CreateGroupDialog from '../components/chatGroups/CreateGroupDialog'
import { useAuth } from '../lib/auth'
import { describeChatGroupError } from '../lib/chatGroupErrors'
import { listGroups, type ChatGroupKind, type ChatGroupSummary } from '../lib/chatGroupsApi'
import { useI18n, useStatusLabel } from '../lib/i18n'
import { usePermission } from '../lib/permissions'

/** What the list area is showing. */
type ListState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; items: ChatGroupSummary[] }

/** Badge tone per kind: distinct colours, neither reads as a warning. */
const KIND_TONE: Record<ChatGroupKind, string> = { masked: 'tone-primary', team: 'tone-info' }

/** How many placeholder rows the skeleton draws. */
const SKELETON_ROWS = 3

/** Resets a list element to a plain vertical stack. */
const PLAIN_LIST = { listStyle: 'none', padding: 0, margin: 0 } as const

export default function ChatGroupsPage() {
  const { t } = useI18n()
  const { user } = useAuth()
  const canCreate = usePermission('messages', 'add', user)
  const [list, setList] = useState<ListState>({ status: 'loading' })
  const [reloadTick, setReloadTick] = useState(0)
  const [creating, setCreating] = useState(false)

  // Loads on mount and on every reload. State is only set once the request
  // settles, never synchronously in the effect.
  useEffect(() => {
    let cancelled = false
    listGroups()
      .then((items) => {
        if (!cancelled) setList({ status: 'ready', items })
      })
      .catch((err: unknown) => {
        if (!cancelled) setList({ status: 'error', message: describeChatGroupError(err) })
      })
    return () => {
      cancelled = true
    }
  }, [reloadTick])

  /** Shows the skeleton again and fetches the list afresh. */
  const reload = useCallback(() => {
    setList({ status: 'loading' })
    setReloadTick((n) => n + 1)
  }, [])

  const openCreate = useCallback(() => setCreating(true), [])
  const closeCreate = useCallback(() => setCreating(false), [])
  const handleCreated = useCallback(() => {
    setCreating(false)
    reload()
  }, [reload])

  return (
    <>
      <PageHead>
        <div>
          <h1>{t('chat_groups.title')}</h1>
          <p className="muted">{t('chat_groups.subtitle')}</p>
        </div>
        {canCreate && (
          <div className="row">
            <button type="button" onClick={openCreate}>
              {t('chat_groups.new_group')}
            </button>
          </div>
        )}
      </PageHead>

      <ListArea list={list} canCreate={canCreate} onRetry={reload} onCreate={openCreate} />

      <AnimatePresence>
        {creating && <CreateGroupDialog key="create-group" onClose={closeCreate} onCreated={handleCreated} />}
      </AnimatePresence>
    </>
  )
}

// ─── The list area: one of the four states ───

type ListAreaProps = {
  list: ListState
  canCreate: boolean
  onRetry: () => void
  onCreate: () => void
}

function ListArea({ list, canCreate, onRetry, onCreate }: ListAreaProps) {
  if (list.status === 'loading') return <ListSkeleton />
  if (list.status === 'error') return <ListError message={list.message} onRetry={onRetry} />
  if (list.items.length === 0) return <EmptyState canCreate={canCreate} onCreate={onCreate} />
  return <GroupList items={list.items} />
}

/** Placeholder rows shaped like GroupRow: a title line over a message line. */
function ListSkeleton() {
  const { t } = useI18n()
  return (
    <div className="card stack" role="status" aria-busy="true" aria-label={t('chat_groups.list.loading')}>
      {Array.from({ length: SKELETON_ROWS }, (_, i) => (
        <div key={i} className="stack" aria-hidden="true">
          <span className="skeleton-line" style={{ display: 'block', width: '35%', height: 14 }} />
          <span className="skeleton-line" style={{ display: 'block', width: '75%', height: 12 }} />
        </div>
      ))}
    </div>
  )
}

/** The reason the list failed, and the way out. */
function ListError({ message, onRetry }: { message: string; onRetry: () => void }) {
  const { t } = useI18n()
  return (
    <div className="card stack">
      <p className="error-box" role="alert" style={{ margin: 0 }}>
        {message}
      </p>
      <div>
        {/* error.retry, the key Table's error row uses. common.retry is
            being added in a separate change; switch once it lands. */}
        <button type="button" className="secondary" onClick={onRetry}>
          {t('error.retry')}
        </button>
      </div>
    </div>
  )
}

/** No groups yet: what they are for, and how to make the first one. */
function EmptyState({ canCreate, onCreate }: { canCreate: boolean; onCreate: () => void }) {
  const { t } = useI18n()
  return (
    <div className="card stack" style={{ textAlign: 'center', paddingBlock: 'var(--space-7)' }}>
      <span aria-hidden="true" style={{ color: 'var(--muted)' }}>
        <Users size={32} strokeWidth={1.8} />
      </span>
      <h2 style={{ margin: 0, fontSize: 'var(--text-lg)' }}>{t('chat_groups.empty.title')}</h2>
      <p className="muted" style={{ margin: 0 }}>
        {t('chat_groups.empty.body')}
      </p>
      {canCreate ? (
        <div>
          <button type="button" onClick={onCreate}>
            {t('chat_groups.empty.cta')}
          </button>
        </div>
      ) : (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_groups.empty.no_permission')}
        </p>
      )}
    </div>
  )
}

/** The groups, most recent activity first (the order the server sends). */
function GroupList({ items }: { items: ChatGroupSummary[] }) {
  const { t } = useI18n()
  return (
    <div className="card">
      <ul className="stack" aria-label={t('chat_groups.list.aria')} style={PLAIN_LIST}>
        {items.map((group) => (
          <GroupRow key={group.id} group={group} />
        ))}
      </ul>
    </div>
  )
}

/** One group: kind badge, name and time on the first line, last message under it. */
function GroupRow({ group }: { group: ChatGroupSummary }) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const name =
    group.kind === 'team' && group.title.trim()
      ? group.title
      : t(group.kind === 'team' ? 'chat_groups.list.team_untitled' : 'chat_groups.list.masked_title', { id: group.id })

  return (
    <li className="stack" style={{ gap: 'var(--space-1)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <span className={`badge ${KIND_TONE[group.kind]}`}>{statusLabel(group.kind)}</span>
        <strong style={{ overflowWrap: 'anywhere' }}>
          <Link to={`/chat-groups/${group.id}`}>{name}</Link>
        </strong>
        {group.last_at && (
          <DateCell value={group.last_at} style={{ marginInlineStart: 'auto', alignItems: 'flex-end' }} />
        )}
      </div>
      <p className="muted" style={{ margin: 0, overflowWrap: 'anywhere' }}>
        {group.last_message || t('chat_groups.list.no_messages')}
      </p>
    </li>
  )
}
