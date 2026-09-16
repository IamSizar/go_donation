/**
 * GroupComposer — staff write into a chat group (Phase 6b).
 *
 * WHEN IT SHOWS (D9)
 *   - the group is paused or ended → the lifecycle notice, with the reason
 *     staff gave, in place of the box;
 *   - the operator lacks messages:add → a line saying why;
 *   - otherwise the box. The page never renders this for a group the operator
 *     cannot read, because it shows the permission state instead.
 *
 * Send stays disabled while the box is blank or a send is in flight. A
 * refusal (contact_details_blocked, chat_lifecycle_closed …) is translated and
 * shown under the box, and the draft is kept so it can be fixed. Enter sends;
 * Shift+Enter adds a line.
 */
import { useId, useState, type FormEvent, type KeyboardEvent } from 'react'
import { describeChatGroupError } from '../../lib/chatGroupErrors'
import { postGroupMessage, type ChatGroupDetail } from '../../lib/chatGroupsApi'
import { useI18n } from '../../lib/i18n'

type Props = {
  group: ChatGroupDetail
  canSend: boolean
  /** Called after the server stored the message, to show it. */
  onSent: () => void | Promise<void>
}

export default function GroupComposer({ group, canSend, onSent }: Props) {
  const { t } = useI18n()
  if (group.lifecycle !== 'open') return <LifecycleNotice group={group} />
  if (!canSend) {
    return (
      <p className="muted" style={{ margin: 0 }}>
        {t('chat_groups.detail.composer_no_permission')}
      </p>
    )
  }
  return <ComposerForm groupId={group.id} onSent={onSent} />
}

/** Why nobody can write: paused or ended, and the reason shown to members. */
function LifecycleNotice({ group }: { group: ChatGroupDetail }) {
  const { t } = useI18n()
  return (
    <div className="info-box stack" role="note">
      <span>{t(group.lifecycle === 'ended' ? 'chat_groups.detail.closed_ended' : 'chat_groups.detail.closed_paused')}</span>
      {group.lifecycle_reason && (
        <span className="muted">{t('chat_lifecycle.reason_shown', { reason: group.lifecycle_reason })}</span>
      )}
    </div>
  )
}

function ComposerForm({ groupId, onSent }: { groupId: number; onSent: Props['onSent'] }) {
  const { t } = useI18n()
  const id = useId()
  const [body, setBody] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const canSubmit = body.trim() !== '' && !busy

  async function send(event?: FormEvent) {
    event?.preventDefault()
    if (!canSubmit) return
    setBusy(true)
    setError(null)
    try {
      await postGroupMessage(groupId, body.trim())
      setBody('')
      await onSent()
    } catch (err) {
      setError(describeChatGroupError(err))
    } finally {
      setBusy(false)
    }
  }

  function onKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      void send()
    }
  }

  return (
    <form className="stack" onSubmit={send} noValidate>
      <label className="form-label" htmlFor={id}>
        {t('chat_groups.detail.composer_label')}
      </label>
      <textarea
        id={id}
        rows={3}
        dir="auto"
        value={body}
        disabled={busy}
        placeholder={t('common.msg_reply_plain')}
        aria-describedby={`${id}-hint`}
        onChange={(e) => {
          setBody(e.target.value)
          setError(null)
        }}
        onKeyDown={onKeyDown}
      />
      <span id={`${id}-hint`} className="form-hint">
        {t('chat_groups.detail.composer_hint')}
      </span>
      {error && (
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {error}
        </p>
      )}
      <div>
        <button type="submit" disabled={!canSubmit} aria-busy={busy || undefined}>
          {busy ? t('common.msg_sending') : t('common.msg_send')}
        </button>
      </div>
    </form>
  )
}
