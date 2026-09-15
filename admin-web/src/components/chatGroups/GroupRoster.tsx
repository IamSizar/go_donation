/**
 * GroupRoster — the members of ONE chat group, and the staff controls that
 * change them (Phase 6b, OPOS #26399).
 *
 * WHAT IT RENDERS (component tree)
 *   GroupRoster
 *   ├── MemberRow ×n         active members: name · role · label (masked) · Remove
 *   ├── toggle + MemberRow   removed members, hidden until asked for
 *   └── AddMemberForm        person · role · label (masked)
 *
 * Staff see real names in every group; a masked member's label is what the
 * other members see instead, so it is shown beside the name.
 *
 * PERMISSIONS
 * Remove and Add need messages:edit (canEdit). Without it the roster is shown
 * read-only with a line saying why. The server remains the control.
 *
 * DATA FLOW
 * The page owns the group. A successful add or remove calls onChanged, and the
 * page fetches the group again, so the roster never drifts from the server.
 */
import { useState } from 'react'
import AddMemberForm from './AddMemberForm'
import { activeMembers, removedMembers } from '../../lib/chatGroupDetail'
import { describeChatGroupError } from '../../lib/chatGroupErrors'
import { removeGroupMember, type ChatGroupDetail, type ChatGroupMember } from '../../lib/chatGroupsApi'
import { formatDateTime } from '../../lib/dates'
import { askToConfirm } from '../../lib/dialogs'
import { useI18n, useStatusLabel } from '../../lib/i18n'
import { useToast } from '../../lib/toast'

type Props = {
  group: ChatGroupDetail
  /** messages:edit — shows Remove and the add form. */
  canEdit: boolean
  /** Called after the roster changed on the server. */
  onChanged: () => void | Promise<void>
}

const PLAIN_LIST = { listStyle: 'none', padding: 0, margin: 0 } as const

export default function GroupRoster({ group, canEdit, onChanged }: Props) {
  const { t } = useI18n()
  const toast = useToast()
  const [showRemoved, setShowRemoved] = useState(false)
  const [busyUserId, setBusyUserId] = useState<number | null>(null)
  const [error, setError] = useState<string | null>(null)
  const active = activeMembers(group.members)
  const removed = removedMembers(group.members)

  /** Confirms, removes, then lets the page refresh. */
  async function remove(member: ChatGroupMember) {
    const name = member.full_name || t('chat_groups.detail.no_profile')
    const sure = await askToConfirm({
      title: t('chat_groups.detail.remove_title'),
      message: t('chat_groups.detail.remove_body', { name }),
      destructive: true,
      confirmLabel: t('chat_groups.create.remove_member'),
    })
    if (!sure) return
    setBusyUserId(member.user_id)
    setError(null)
    try {
      await removeGroupMember(group.id, member.user_id)
      toast.success(t('chat_groups.detail.removed_toast'))
      await onChanged()
    } catch (err) {
      setError(describeChatGroupError(err))
    } finally {
      setBusyUserId(null)
    }
  }

  return (
    <section className="card stack" aria-labelledby={`roster-${group.id}`}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <strong id={`roster-${group.id}`}>{t('chat_groups.create.members_label')}</strong>
        <span className="muted">{t('chat_groups.detail.active_count', { n: active.length })}</span>
      </div>
      {error && (
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {error}
        </p>
      )}
      {active.length === 0 ? (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_groups.detail.roster_empty')}
        </p>
      ) : null}
      <ul className="stack" aria-label={t('chat_groups.create.members_label')} style={PLAIN_LIST}>
        {active.map((member) => (
          <MemberRow
            key={member.id}
            member={member}
            onRemove={canEdit ? () => void remove(member) : undefined}
            busy={busyUserId === member.user_id}
          />
        ))}
      </ul>
      {removed.length > 0 && (
        <div>
          <button type="button" className="secondary" onClick={() => setShowRemoved((v) => !v)} aria-expanded={showRemoved}>
            {showRemoved
              ? t('chat_groups.detail.hide_removed')
              : t('chat_groups.detail.show_removed', { n: removed.length })}
          </button>
        </div>
      )}
      {showRemoved && (
        <ul className="stack" aria-label={t('chat_groups.detail.removed_aria')} style={PLAIN_LIST}>
          {removed.map((member) => (
            <MemberRow key={member.id} member={member} busy={false} />
          ))}
        </ul>
      )}
      {canEdit ? (
        <AddMemberForm group={group} onAdded={onChanged} />
      ) : (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_groups.detail.no_edit')}
        </p>
      )}
    </section>
  )
}

// ─── One member ───

type RowProps = {
  member: ChatGroupMember
  /** Absent for a removed member, or for staff without messages:edit. */
  onRemove?: () => void
  busy: boolean
}

/** Name, role, masked label, and Remove or the removal date. */
function MemberRow({ member, onRemove, busy }: RowProps) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const name = member.full_name || t('chat_groups.detail.no_profile')

  return (
    <li style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
      <strong style={{ overflowWrap: 'anywhere' }}>{name}</strong>
      <span className="badge tone-info">{statusLabel(member.role_in_group)}</span>
      {member.masked && member.masked_label && (
        <span className="muted">{t('chat_groups.detail.label_of', { label: member.masked_label })}</span>
      )}
      {member.removed_at ? (
        <span style={{ marginInlineStart: 'auto', display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
          <span className="badge tone-warning">{t('chat_groups.detail.removed')}</span>
          <time className="muted" dateTime={member.removed_at}>
            {formatDateTime(member.removed_at)}
          </time>
        </span>
      ) : (
        onRemove && (
          <button
            type="button"
            className="secondary"
            style={{ marginInlineStart: 'auto' }}
            onClick={onRemove}
            disabled={busy}
            aria-label={t('chat_groups.detail.remove_aria', { name })}
          >
            {t('chat_groups.create.remove_member')}
          </button>
        )
      )}
    </li>
  )
}
