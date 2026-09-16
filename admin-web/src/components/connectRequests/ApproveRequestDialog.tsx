/**
 * ApproveRequestDialog — approves a pending connect request by opening its
 * group (Phase 6c, OPOS #26400).
 *
 * WHAT IT RENDERS
 *   DialogFrame
 *   ├── KindCards         masked vs team (6a)
 *   ├── TeamTitleField    team only; required (D7)
 *   └── Members fieldset
 *       └── MemberRowsEditor  (6a; the D2 guidance card without users:view)
 *
 * DATA FLOW
 * The draft starts with the requester in member row 1 (approveDraftFor),
 * because ApproveConnectRequest refuses a body without them. Every change
 * re-runs 6a's validateGroupDraft plus requesterIssue; Approve stays disabled
 * until both pass, and the requester rule is shown whenever it is broken.
 *
 * The body is 6a's buildCreateGroupBody — exactly what the handler binds
 * (adminCreateGroupReq: kind, member_title, members[{user_id, role_in_group,
 * label}]). Success: a toast, then onApproved(groupId). A refusal is
 * translated by describeConnectRequestError and placed by chatGroupErrorArea:
 * beside the members when it is about them, atop the form otherwise.
 */
import { AnimatePresence, motion } from 'framer-motion'
import { useId, useMemo, useState, type FormEvent } from 'react'
import DialogFrame from './DialogFrame'
import FieldNote from '../chatGroups/FieldNote'
import KindCards from '../chatGroups/KindCards'
import MemberRowsEditor from '../chatGroups/MemberRowsEditor'
import TeamTitleField from '../chatGroups/TeamTitleField'
import {
  chatGroupErrorArea, describeConnectRequestError, type ChatGroupErrorArea,
} from '../../lib/chatGroupErrors'
import { buildCreateGroupBody, validateGroupDraft, visibleIssues, type GroupDraft } from '../../lib/chatGroupForm'
import { approveConnectRequest, type ConnectRequest } from '../../lib/chatGroupsApi'
import { approveDraftFor, requesterIssue } from '../../lib/connectRequestForm'
import { useI18n } from '../../lib/i18n'
import { useToast } from '../../lib/toast'

type Props = {
  request: ConnectRequest
  onClose: () => void
  /** Called with the new group's id after the server approved the request. */
  onApproved: (groupId: number) => void
}

/** A refusal from the server, and where in the form it belongs. */
type SubmitError = { message: string; area: ChatGroupErrorArea }

export default function ApproveRequestDialog({ request, onClose, onApproved }: Props) {
  const { t } = useI18n()
  const toast = useToast()
  const requesterNoteId = useId()
  const [draft, setDraft] = useState<GroupDraft>(() => approveDraftFor(request))
  const [touched, setTouched] = useState<ReadonlySet<string>>(() => new Set())
  const [busy, setBusy] = useState(false)
  const [submitError, setSubmitError] = useState<SubmitError | null>(null)
  const validation = useMemo(() => validateGroupDraft(draft), [draft])
  const missingRequester = requesterIssue(draft, request.requester_user_id)
  const canSubmit = validation.isValid && !missingRequester
  const shown = visibleIssues(validation.issues, touched)

  function touch(fieldId: string) {
    setTouched((prev) => (prev.has(fieldId) ? prev : new Set(prev).add(fieldId)))
  }

  function update(patch: Partial<GroupDraft>) {
    setDraft((prev) => ({ ...prev, ...patch }))
    setSubmitError(null)
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!canSubmit || busy) return
    setBusy(true)
    setSubmitError(null)
    try {
      const groupId = await approveConnectRequest(request.id, buildCreateGroupBody(draft))
      toast.success(t('chat_groups.inbox.approve.approved_toast'))
      onApproved(groupId)
    } catch (err) {
      setSubmitError({ message: describeConnectRequestError(err), area: chatGroupErrorArea(err) })
      setBusy(false)
    }
  }

  const footer = (
    <>
      {!canSubmit && (
        <span className="muted" style={{ marginInlineEnd: 'auto', fontSize: 'var(--text-xs)' }}>
          {t('chat_groups.inbox.approve.gated_hint')}
        </span>
      )}
      <button type="button" className="secondary" onClick={onClose} disabled={busy}>
        {t('common.cancel')}
      </button>
      <button type="submit" disabled={!canSubmit || busy} aria-busy={busy || undefined}>
        {busy ? t('chat_groups.inbox.approve.submitting') : t('chat_groups.inbox.approve.submit')}
      </button>
    </>
  )

  return (
    <DialogFrame
      title={t('chat_groups.inbox.approve.title')}
      busy={busy}
      onClose={onClose}
      onSubmit={submit}
      width="min(720px, 94vw)"
      footer={footer}
    >
      {submitError?.area === 'form' && (
        <p className="error-box" role="alert" style={{ margin: 0 }}>
          {submitError.message}
        </p>
      )}
      <p className="muted" style={{ margin: 0 }}>
        {t('chat_groups.inbox.approve.intro')}
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
        <FieldNote id={requesterNoteId} issue={missingRequester} />
        <FieldNote id={`${requesterNoteId}-members`} issue={shown.members} />
        <MemberRowsEditor
          kind={draft.kind}
          rows={draft.members}
          issues={shown.rows}
          disabled={busy}
          onRowsChange={(members) => update({ members })}
          onTouch={touch}
        />
      </fieldset>
    </DialogFrame>
  )
}
