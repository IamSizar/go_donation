/**
 * AddMemberForm — adds one person to an existing chat group (Phase 6b).
 *
 * WHAT IT RENDERS
 * The same three fields as a member row of 6a's create dialog: the person
 * (UserPicker), their role in the group, and, for a masked group only, the
 * label other members see. The rules are 6a's (lib/chatGroupForm.ts) checked
 * against the members already in the group (lib/chatGroupDetail.ts):
 *   - an active member cannot be added twice;
 *   - a removed member can be added back, and keeps their old role and label
 *     (decision D3), which a hint says before the operator submits;
 *   - a label an active member already has is refused; a label that looks
 *     like a phone or email gets a warning, not a block.
 * Add member stays disabled until nothing blocks, so a doomed request is
 * never sent. Issues show only on fields the operator has touched.
 *
 * WHO CAN PICK PEOPLE (decision D2)
 * The picker searches users, which needs users:view; without it the form is
 * replaced by 6a's guidance card.
 *
 * On success the draft is cleared, a toast confirms it, and onAdded lets the
 * page refresh. A refusal is translated and shown in the form, draft kept.
 */
import { useId, useMemo, useState, type FormEvent } from 'react'
import FieldNote from './FieldNote'
import { UserSearchGuidance } from './MemberRowsEditor'
import UserPicker from '../UserPicker'
import { useAuth } from '../../lib/auth'
import { buildAddMemberBody, emptyAddMemberDraft, validateAddMember, type AddMemberDraft } from '../../lib/chatGroupDetail'
import { describeChatGroupError } from '../../lib/chatGroupErrors'
import { CHAT_GROUP_ROLES, isChatGroupRole, type MemberRowIssues } from '../../lib/chatGroupForm'
import { addGroupMember, type ChatGroupDetail } from '../../lib/chatGroupsApi'
import { useI18n, useStatusLabel } from '../../lib/i18n'
import { usePermission } from '../../lib/permissions'
import { useToast } from '../../lib/toast'

type Props = {
  group: ChatGroupDetail
  onAdded: () => void | Promise<void>
}

type Field = 'user' | 'role' | 'label'

export default function AddMemberForm({ group, onAdded }: Props) {
  const { t } = useI18n()
  const { user } = useAuth()
  const toast = useToast()
  const headingId = useId()
  const canSearchUsers = usePermission('users', 'view', user)
  const [draft, setDraft] = useState<AddMemberDraft>(emptyAddMemberDraft)
  const [touched, setTouched] = useState<ReadonlySet<Field>>(() => new Set())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const validation = useMemo(() => validateAddMember(draft, group), [draft, group])

  function change(patch: Partial<AddMemberDraft>, field: Field) {
    setDraft((prev) => ({ ...prev, ...patch }))
    setTouched((prev) => new Set(prev).add(field))
    setError(null)
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!validation.isValid || busy) return
    setBusy(true)
    setError(null)
    try {
      await addGroupMember(group.id, buildAddMemberBody(draft, group.kind))
      toast.success(t('chat_groups.detail.added_toast'))
      setDraft(emptyAddMemberDraft())
      setTouched(new Set())
      await onAdded()
    } catch (err) {
      setError(describeChatGroupError(err))
    } finally {
      setBusy(false)
    }
  }

  const shown: MemberRowIssues = {
    user: touched.has('user') ? validation.issues.user : undefined,
    role: touched.has('role') ? validation.issues.role : undefined,
    label: touched.has('label') ? validation.issues.label : undefined,
    labelHint: touched.has('label') ? validation.issues.labelHint : undefined,
  }

  return (
    <form className="stack" aria-labelledby={headingId} onSubmit={submit} noValidate>
      <strong id={headingId}>{t('chat_groups.detail.add_title')}</strong>
      {canSearchUsers ? (
        <>
          {error && (
            <p className="error-box" role="alert" style={{ margin: 0 }}>
              {error}
            </p>
          )}
          <AddMemberFields group={group} draft={draft} issues={shown} busy={busy} onChange={change} />
          {validation.reactivates && (
            <p className="info-box" style={{ margin: 0 }}>
              {t('chat_groups.detail.reactivate_hint')}
            </p>
          )}
          <div>
            <button type="submit" disabled={!validation.isValid || busy} aria-busy={busy || undefined}>
              {busy ? t('chat_groups.detail.adding') : t('chat_groups.create.add_member')}
            </button>
          </div>
        </>
      ) : (
        <UserSearchGuidance />
      )}
    </form>
  )
}

// ─── The fields ───

type FieldsProps = {
  group: ChatGroupDetail
  draft: AddMemberDraft
  issues: MemberRowIssues
  busy: boolean
  onChange: (patch: Partial<AddMemberDraft>, field: Field) => void
}

/** Person, role and (masked only) label, each with its note. */
function AddMemberFields({ group, draft, issues, busy, onChange }: FieldsProps) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const id = useId()

  return (
    <div className="form-grid">
      <div className="form-row field">
        <span className="form-label">{t('chat_groups.create.person_label')}</span>
        <UserPicker value={draft.user} onChange={(user) => onChange({ user }, 'user')} disabled={busy} />
        <FieldNote id={`${id}-user`} issue={issues.user} />
      </div>
      <div className="form-row field">
        <label className="form-label" htmlFor={`${id}-role`}>
          {t('chat_groups.create.role_label')}
        </label>
        <select
          id={`${id}-role`}
          value={draft.role}
          disabled={busy}
          aria-invalid={issues.role ? true : undefined}
          onChange={(e) => onChange({ role: isChatGroupRole(e.target.value) ? e.target.value : '' }, 'role')}
        >
          <option value="">{t('chat_groups.create.role_placeholder')}</option>
          {CHAT_GROUP_ROLES.map((role) => (
            <option key={role} value={role}>
              {statusLabel(role)}
            </option>
          ))}
        </select>
        <FieldNote id={`${id}-role-note`} issue={issues.role} />
      </div>
      {group.kind === 'masked' && (
        <div className="form-row field">
          <label className="form-label" htmlFor={`${id}-label`}>
            {t('chat_groups.create.label_label')}
          </label>
          <input
            id={`${id}-label`}
            type="text"
            dir="auto"
            autoComplete="off"
            value={draft.label}
            disabled={busy}
            placeholder={t('chat_groups.create.label_placeholder')}
            aria-invalid={issues.label ? true : undefined}
            onChange={(e) => onChange({ label: e.target.value }, 'label')}
          />
          <span className="form-hint">{t('chat_groups.create.label_hint')}</span>
          <FieldNote id={`${id}-label-note`} issue={issues.label} />
          {issues.labelHint && (
            <span className="form-hint" style={{ color: 'var(--tone-warning-fg)' }}>
              {t(issues.labelHint.key)}
            </span>
          )}
        </div>
      )}
    </div>
  )
}
