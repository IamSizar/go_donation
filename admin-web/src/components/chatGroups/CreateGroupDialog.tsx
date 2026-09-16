/**
 * CreateGroupDialog — staff create a chat group and add its first members.
 *
 * WHAT IT RENDERS (component tree)
 *   CreateGroupDialog
 *   ├── KindCards           masked vs team, as two selectable cards
 *   ├── TeamTitleField      team only; required, at most 200 characters (D7)
 *   └── Members (fieldset)
 *       └── MemberRowsEditor  person · role · label (masked only), per row
 *
 * DATA FLOW
 * The dialog owns the draft. Every change re-runs validateGroupDraft
 * (lib/chatGroupForm.ts). Create group stays disabled until nothing blocks,
 * so a doomed request is never sent. Issues are drawn only on fields the
 * operator has touched, so an untouched form is not painted red on open.
 *
 * On submit it POSTs buildCreateGroupBody(draft) through createGroup. Success
 * shows a toast and calls onCreated(groupId); the page closes the dialog and
 * refreshes its list. A refusal is translated by describeChatGroupError and
 * shown inside the dialog, beside the members when it is about them, and the
 * draft is kept so the operator can fix it and try again.
 *
 * MOUNTING
 * The page mounts this only while it is open (inside AnimatePresence), so
 * every opening starts from an empty draft with no reset logic.
 */
import { AnimatePresence, motion } from 'framer-motion'
import { useId, useMemo, useRef, useState, type FormEvent } from 'react'
import FieldNote from './FieldNote'
import KindCards from './KindCards'
import MemberRowsEditor from './MemberRowsEditor'
import TeamTitleField from './TeamTitleField'
import { useDialogKeyboard } from './useDialogKeyboard'
import { chatGroupErrorArea, describeChatGroupError, type ChatGroupErrorArea } from '../../lib/chatGroupErrors'
import {
  buildCreateGroupBody,
  emptyGroupDraft,
  validateGroupDraft,
  visibleIssues,
  type GroupDraft,
} from '../../lib/chatGroupForm'
import { createGroup } from '../../lib/chatGroupsApi'
import { useI18n } from '../../lib/i18n'
import { useToast } from '../../lib/toast'

type Props = {
  /** Called when the operator dismisses the dialog without creating. */
  onClose: () => void
  /** Called with the new group's id after the server created it. */
  onCreated: (groupId: number) => void
}

/** A refusal from the server, and where in the form it belongs. */
type SubmitError = { message: string; area: ChatGroupErrorArea }

export default function CreateGroupDialog({ onClose, onCreated }: Props) {
  const { t } = useI18n()
  const toast = useToast()
  const headingId = useId()
  const membersNoteId = useId()
  const cardRef = useRef<HTMLDivElement>(null)
  const [draft, setDraft] = useState<GroupDraft>(emptyGroupDraft)
  const [touched, setTouched] = useState<ReadonlySet<string>>(() => new Set())
  const [busy, setBusy] = useState(false)
  const [submitError, setSubmitError] = useState<SubmitError | null>(null)
  const validation = useMemo(() => validateGroupDraft(draft), [draft])
  const shown = visibleIssues(validation.issues, touched)
  useDialogKeyboard(cardRef, busy ? null : onClose)

  // ─── Draft changes ───

  function touch(fieldId: string) {
    setTouched((prev) => (prev.has(fieldId) ? prev : new Set(prev).add(fieldId)))
  }

  /** Applies a change and clears a refusal that was about the old draft. */
  function update(patch: Partial<GroupDraft>) {
    setDraft((prev) => ({ ...prev, ...patch }))
    setSubmitError(null)
  }

  // ─── Submit ───

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!validation.isValid || busy) return
    setBusy(true)
    setSubmitError(null)
    try {
      const groupId = await createGroup(buildCreateGroupBody(draft))
      toast.success(t('chat_groups.create.created_toast'))
      onCreated(groupId)
    } catch (err) {
      setSubmitError({ message: describeChatGroupError(err), area: chatGroupErrorArea(err) })
      setBusy(false)
    }
  }

  // ─── Render ───

  return (
    <motion.div
      className="modal-overlay"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.18 }}
      onMouseDown={(e) => {
        // mousedown, not click: a text selection that ends on the backdrop
        // must not throw the draft away.
        if (e.target === e.currentTarget && !busy) onClose()
      }}
    >
      <motion.div
        ref={cardRef}
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-labelledby={headingId}
        style={{ width: 'min(720px, 94vw)' }}
        initial={{ opacity: 0, scale: 0.94, y: 12 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.96, y: 8 }}
        transition={{ type: 'spring', stiffness: 320, damping: 28 }}
      >
        <form
          onSubmit={submit}
          noValidate
          style={{ display: 'flex', flexDirection: 'column', flex: '1 1 auto', minHeight: 0 }}
        >
          <div className="modal-head">
            <h2 id={headingId}>{t('chat_groups.create.title')}</h2>
            <button type="button" className="icon" onClick={onClose} disabled={busy} aria-label={t('common.close')}>
              ×
            </button>
          </div>

          <div className="modal-body stack">
            {submitError?.area === 'form' && (
              <p className="error-box" role="alert" style={{ margin: 0 }}>
                {submitError.message}
              </p>
            )}
            <p className="muted" style={{ margin: 0 }}>
              {t('chat_groups.create.intro')}
            </p>
            <KindCards
              value={draft.kind}
              disabled={busy}
              onChange={(kind) => {
                update({ kind })
                touch('kind')
              }}
            />
            <AnimatePresence initial={false}>
              {draft.kind === 'team' && (
                <motion.div
                  key="team-title"
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={{ duration: 0.18 }}
                  style={{ overflow: 'hidden' }}
                >
                  <TeamTitleField
                    value={draft.title}
                    issue={shown.title}
                    disabled={busy}
                    onChange={(title) => {
                      update({ title })
                      touch('title')
                    }}
                    onBlur={() => touch('title')}
                  />
                </motion.div>
              )}
            </AnimatePresence>

            <fieldset className="stack" style={{ border: 0, padding: 0, margin: 0, minWidth: 0 }}>
              <legend className="form-label" style={{ marginBlockEnd: 'var(--space-2)' }}>
                {t('chat_groups.create.members_label')}
              </legend>
              {submitError?.area === 'members' && (
                <p className="error-box" role="alert" style={{ margin: 0 }}>
                  {submitError.message}
                </p>
              )}
              <FieldNote id={membersNoteId} issue={shown.members} />
              <MemberRowsEditor
                kind={draft.kind}
                rows={draft.members}
                issues={shown.rows}
                disabled={busy}
                onRowsChange={(members) => update({ members })}
                onTouch={touch}
              />
            </fieldset>
          </div>

          <div className="modal-foot" style={{ alignItems: 'center' }}>
            {!validation.isValid && (
              <span className="muted" style={{ marginInlineEnd: 'auto', fontSize: 'var(--text-xs)' }}>
                {t('chat_groups.create.gated_hint')}
              </span>
            )}
            <button type="button" className="secondary" onClick={onClose} disabled={busy}>
              {t('common.cancel')}
            </button>
            <button type="submit" disabled={!validation.isValid || busy} aria-busy={busy || undefined}>
              {busy ? t('chat_groups.create.submitting') : t('chat_groups.create.submit')}
            </button>
          </div>
        </form>
      </motion.div>
    </motion.div>
  )
}

