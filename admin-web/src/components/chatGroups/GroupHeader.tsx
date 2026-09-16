/**
 * GroupHeader — the top of the chat-group detail page (Phase 6b).
 *
 * WHAT IT RENDERS
 *   - the way back to the list, the kind badge and the group's name (a team
 *     group's title; a masked group, which has none, by its id);
 *   - the export (E3): ExportCsvButton, whose rows load only after the PIN,
 *     through the same messages route this page reads;
 *   - the group's state: ChatLifecycleControls for staff with messages:edit,
 *     the same state read-only (badge, archived flag, reason) for the rest.
 */
import { Link } from 'react-router-dom'
import ChatLifecycleControls from '../ChatLifecycleControls'
import ExportCsvButton from '../ExportCsvButton'
import PageHead from '../PageHead'
import { chatExportFilenameBase, chatExportTitle, groupChatExportColumns } from '../../lib/chatExport'
import { loadGroupChatExport } from '../../lib/chatGroupDetail'
import type { ChatGroupDetail } from '../../lib/chatGroupsApi'
import { useI18n, useStatusLabel } from '../../lib/i18n'

type Props = {
  group: ChatGroupDetail
  /** messages:edit — shows the lifecycle controls. */
  canEdit: boolean
  /** Called after a lifecycle action or a delete. */
  onLifecycleChanged: () => void | Promise<void>
}

const EXPORT_COLUMNS = groupChatExportColumns()

/** The group's display name: a team's title, else "Masked group #T41". */
function useGroupName(group: Pick<ChatGroupDetail, 'id' | 'kind' | 'member_title'>): string {
  const { t } = useI18n()
  if (group.kind === 'team' && group.member_title.trim()) return group.member_title
  return t(group.kind === 'team' ? 'chat_groups.list.team_untitled' : 'chat_groups.list.masked_title', { id: group.id })
}

export default function GroupHeader({ group, canEdit, onLifecycleChanged }: Props) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const name = useGroupName(group)

  return (
    <>
      <p style={{ margin: 0 }}>
        <Link to="/chat-groups">{t('chat_groups.detail.back')}</Link>
      </p>
      <PageHead>
        <div className="stack" style={{ gap: 'var(--space-1)' }}>
          <span>
            <span className={`badge ${group.kind === 'masked' ? 'tone-primary' : 'tone-info'}`}>{statusLabel(group.kind)}</span>
          </span>
          <h1 style={{ overflowWrap: 'anywhere' }}>{name}</h1>
          {group.kind === 'masked' && <p className="muted">{t('chat_groups.detail.masked_note')}</p>}
        </div>
        <div className="row">
          <ExportCsvButton
            loadRows={() => loadGroupChatExport(group)}
            columns={EXPORT_COLUMNS}
            filenameBase={chatExportFilenameBase('group', group.id)}
            title={chatExportTitle('group', group.id)}
            module="messages"
            label={t('export.conversation')}
          />
        </div>
      </PageHead>
      <section className="card" aria-label={t('chat_groups.detail.state_aria')}>
        {canEdit ? (
          <ChatLifecycleControls basePath={`/api/admin/chat-groups/${group.id}`} deleteModule="messages" thread={group} onChanged={onLifecycleChanged} />
        ) : (
          <ReadOnlyState group={group} />
        )}
      </section>
    </>
  )
}

/** The lifecycle state without controls. */
function ReadOnlyState({ group }: { group: ChatGroupDetail }) {
  const { t } = useI18n()
  const tone = group.lifecycle === 'ended' ? 'info' : group.lifecycle === 'paused' ? 'warning' : 'success'
  return (
    <div className="stack" style={{ gap: 'var(--space-1)' }}>
      <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <span className={`badge tone-${tone}`}>{t(`status.${group.lifecycle}`)}</span>
        {group.is_archived && <span className="badge tone-info">{t('status.archived')}</span>}
      </div>
      {group.lifecycle_reason && (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_lifecycle.reason_shown', { reason: group.lifecycle_reason })}
        </p>
      )}
    </div>
  )
}
