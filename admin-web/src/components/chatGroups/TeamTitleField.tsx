/**
 * TeamTitleField — a team group's name, with its limit as a standing hint and
 * the broken rule under it (decision D7: a team group must be named).
 *
 * Moved out of CreateGroupDialog so the connect-request Approve dialog
 * (Phase 6c) draws the same field with the same rules; both dialogs own the
 * draft and pass the issue from lib/chatGroupForm.ts's validateGroupDraft.
 */
import { useId } from 'react'
import FieldNote from './FieldNote'
import { TEAM_TITLE_MAX_LENGTH, type FieldMessage } from '../../lib/chatGroupForm'
import { useI18n } from '../../lib/i18n'

type Props = {
  value: string
  /** The broken rule, already filtered to a touched field. */
  issue?: FieldMessage
  disabled: boolean
  onChange: (title: string) => void
  onBlur: () => void
}

export default function TeamTitleField({ value, issue, disabled, onChange, onBlur }: Props) {
  const { t } = useI18n()
  const id = useId()
  const hintId = `${id}-hint`
  const errorId = `${id}-error`

  return (
    <div className="form-row field">
      <label className="form-label" htmlFor={id}>
        {t('chat_groups.create.title_label')}
      </label>
      <input
        id={id}
        type="text"
        value={value}
        dir="auto"
        autoComplete="off"
        disabled={disabled}
        aria-invalid={issue ? true : undefined}
        aria-describedby={issue ? `${hintId} ${errorId}` : hintId}
        onChange={(e) => onChange(e.target.value)}
        onBlur={onBlur}
      />
      <span id={hintId} className="form-hint">
        {t('chat_groups.create.title_hint', { max: TEAM_TITLE_MAX_LENGTH })}
      </span>
      <FieldNote id={errorId} issue={issue} />
    </div>
  )
}
