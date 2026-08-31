/**
 * ChatLifecycleControls — the staff moderation strip for ONE chat thread.
 *
 * The product has four separate chat systems (donor ↔ owner, marriage,
 * staff ↔ staff, staff ↔ volunteer ↔ beneficiary) and every one of them gets
 * the same five actions, so this is one component the four pages drop in
 * rather than four near-identical copies that would drift apart.
 *
 *   Pause / Resume — temporary and reversible. Nobody can send while paused;
 *                    both participants keep reading and are shown the reason.
 *   End            — final. Read-only for everyone; the history is kept.
 *                    There is no un-end, so it is confirmed before it fires.
 *   Archive /      — hides the thread from the PARTICIPANTS. Staff keep
 *   Unarchive        seeing it here, and can put it back.
 *   Delete         — to the Trash, where a Super-Admin can restore or
 *                    permanently destroy it.
 *
 * Only staff ever see this: the whole dashboard is behind a staff session,
 * and the endpoints it calls live on the admin route group. The app has no
 * equivalent.
 *
 * All four async states are covered: the strip is disabled while a request is
 * in flight (loading), reflects the returned state (content), surfaces a
 * friendly reason on failure (error), and simply renders nothing when there
 * is no thread selected (empty).
 */
import { useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { askForText, askToConfirm } from '../lib/dialogs'

/** The lifecycle a thread can be in, as the API reports it. */
export type ChatLifecycle = 'open' | 'paused' | 'ended'

/** The shape every chat page's thread row shares, as far as this strip cares. */
export type LifecycleThread = {
  id: number
  lifecycle?: ChatLifecycle
  lifecycle_reason?: string | null
  is_archived?: boolean
}

type Props = {
  /**
   * The admin base path of THIS chat system's thread, without a trailing
   * slash — e.g. `/api/admin/chats/12`. Passed in rather than derived from a
   * "kind" string so each page states its own route explicitly and a typo is
   * a compile-time-visible literal instead of a silent mapping miss.
   */
  basePath: string
  thread: LifecycleThread
  /** Re-fetch the page's list once the state has actually changed. */
  onChanged: () => void | Promise<void>
}

export default function ChatLifecycleControls({ basePath, thread, onChanged }: Props) {
  const { t } = useI18n()
  const [busy, setBusy] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)

  const lifecycle: ChatLifecycle = thread.lifecycle ?? 'open'
  const archived = thread.is_archived === true
  const ended = lifecycle === 'ended'
  const paused = lifecycle === 'paused'

  /**
   * run — every action goes through here so the in-flight state, the error
   * surface and the refresh are identical for all of them, and so no button
   * can be double-fired.
   */
  async function run(action: string, reason?: string) {
    if (busy) return
    setBusy(action)
    setErr(null)
    try {
      await api.post(`${basePath}/lifecycle`, { action, reason: reason ?? '' })
      await onChanged()
    } catch (e) {
      // Never swallowed: the operator sees the server's own explanation
      // (e.g. "ending is final"), not a silent no-op.
      setErr(describeError(e))
    } finally {
      setBusy(null)
    }
  }

  /**
   * Pause and End both ask for a reason, because that reason is what the two
   * participants are shown in place of their composer. A chat that stops
   * working without saying why is the failure this whole feature exists to
   * avoid, so the prompt is offered every time — though an empty answer is
   * accepted, since a staff member should never be blocked from stopping a
   * conversation that needs stopping.
   */
  async function askReasonThen(action: 'pause' | 'end') {
    const reason = await askForText({
      title: t(action === 'pause' ? 'chat_lifecycle.pause' : 'chat_lifecycle.end'),
      message: t('chat_lifecycle.reason_prompt'),
      placeholder: t('chat_lifecycle.reason_placeholder'),
      confirmLabel: t('common.confirm'),
    })
    if (reason === null) return // backed out
    if (action === 'end') {
      const sure = await askToConfirm({
        title: t('chat_lifecycle.end'),
        message: t('chat_lifecycle.end_confirm'),
        destructive: true,
        confirmLabel: t('chat_lifecycle.end'),
      })
      if (!sure) return
    }
    await run(action, reason)
  }

  async function remove() {
    const sure = await askToConfirm({
      title: t('chat_lifecycle.delete'),
      message: t('chat_lifecycle.delete_confirm'),
      destructive: true,
      confirmLabel: t('chat_lifecycle.delete'),
    })
    if (!sure) return
    if (busy) return
    setBusy('delete')
    setErr(null)
    try {
      await api.delete(basePath)
      await onChanged()
    } catch (e) {
      setErr(describeError(e))
    } finally {
      setBusy(null)
    }
  }

  return (
    <div className="stack" style={{ gap: 6 }}>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' }}>
        {/* Current state, always visible — the buttons alone would not say
            whether a chat is already paused. */}
        <span className={`badge tone-${ended ? 'info' : paused ? 'warning' : 'success'}`}>
          {t(`status.${lifecycle}`)}
        </span>
        {archived && <span className="badge tone-info">{t('status.archived')}</span>}

        {/* Pause is only offered on an open chat; Resume only on a paused one.
            Neither is offered on an ended chat — ending is final. */}
        {!ended && !paused && (
          <button className="secondary" disabled={busy !== null} onClick={() => askReasonThen('pause')}>
            {busy === 'pause' ? t('common.saving') : t('chat_lifecycle.pause')}
          </button>
        )}
        {!ended && paused && (
          <button className="secondary" disabled={busy !== null} onClick={() => run('resume')}>
            {busy === 'resume' ? t('common.saving') : t('chat_lifecycle.resume')}
          </button>
        )}
        {!ended && (
          <button className="secondary" disabled={busy !== null} onClick={() => askReasonThen('end')}>
            {busy === 'end' ? t('common.saving') : t('chat_lifecycle.end')}
          </button>
        )}

        <button
          className="secondary"
          disabled={busy !== null}
          onClick={() => run(archived ? 'unarchive' : 'archive')}
        >
          {busy === 'archive' || busy === 'unarchive'
            ? t('common.saving')
            : t(archived ? 'chat_lifecycle.unarchive' : 'chat_lifecycle.archive')}
        </button>

        <button className="danger" disabled={busy !== null} onClick={remove}>
          {busy === 'delete' ? t('common.saving') : t('chat_lifecycle.delete')}
        </button>
      </div>

      {/* The reason staff gave, echoed back so they can see what the two
          participants are currently being told. */}
      {thread.lifecycle_reason && (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_lifecycle.reason_shown', { reason: thread.lifecycle_reason })}
        </p>
      )}
      {archived && (
        <p className="muted" style={{ margin: 0 }}>
          {t('chat_lifecycle.archived_hint')}
        </p>
      )}
      {err && (
        <p className="error-box" style={{ margin: 0 }}>
          {err}
        </p>
      )}
    </div>
  )
}
