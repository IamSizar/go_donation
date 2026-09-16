/**
 * FieldNote — the inline message under one form field in the chat-group forms.
 *
 * Renders a rule the field breaks (from lib/chatGroupForm.ts, as an i18n key
 * with its values) in the dashboard's `.field-error` style, directly under the
 * control, so the operator reads what to fix where they are typing. The `id`
 * is what the control's aria-describedby points at, so a screen reader reads
 * the same sentence. Renders nothing when there is no issue.
 *
 * Used by CreateGroupDialog (the team name) and MemberRowsEditor (person,
 * role and label on each row).
 */
import type { FieldMessage } from '../../lib/chatGroupForm'
import { useI18n } from '../../lib/i18n'

type Props = {
  /** The element id the field's aria-describedby names. */
  id: string
  /** The broken rule, or undefined when the field is fine. */
  issue?: FieldMessage
}

export default function FieldNote({ id, issue }: Props) {
  const { t } = useI18n()
  if (!issue) return null
  return (
    <span id={id} className="field-error">
      {t(issue.key, issue.vars)}
    </span>
  )
}
