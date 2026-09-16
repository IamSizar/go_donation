/**
 * MemberRowsEditor — the member rows of the create-group dialog.
 *
 * WHAT IT RENDERS
 * One card per member: who (the existing UserPicker), their role in the group,
 * and, for a masked group only, the label the other members will see instead
 * of their name. An "Add member" button appends a row; each row has its own
 * Remove button. Rows are numbered by position, so removing one renumbers the
 * rest.
 *
 * TEAM GROUPS OFFER TWO ROLES ONLY
 * A team group shows its members each other's real names, so the server takes
 * only volunteer and staff accounts in one and refuses a grantor or a
 * recipient (400 team_member_role_not_allowed). The role select therefore
 * lists only what the server would accept (rolesForKind, lib/chatGroupForm.ts),
 * with one line under it saying why.
 *
 * WHO CAN PICK MEMBERS (decision D2)
 * Picking uses the users search, GET /api/admin/users?q=, which needs
 * users:view. Staff without it would get a search box whose every request is
 * refused, so they get a guidance card instead that says why and what to do.
 * The server remains the control; this only keeps the screen honest.
 *
 * DATA FLOW
 * The dialog owns the rows. This component reports every change through
 * onRowsChange and every touched field through onTouch, and draws the issues
 * it is given; it holds no state of its own.
 */
import { useId } from 'react'
import FieldNote from './FieldNote'
import UserPicker from '../UserPicker'
import { useAuth } from '../../lib/auth'
import {
  emptyMemberDraft,
  isChatGroupRole,
  memberFieldId,
  nextMemberKey,
  rolesForKind,
  type MemberDraft,
  type MemberField,
  type MemberRowIssues,
} from '../../lib/chatGroupForm'
import type { ChatGroupKind } from '../../lib/chatGroupsApi'
import { useI18n, useStatusLabel } from '../../lib/i18n'
import { usePermission } from '../../lib/permissions'

type Props = {
  /** The group's kind; the label field shows only for 'masked'. */
  kind: ChatGroupKind | null
  rows: MemberDraft[]
  /** Issues to draw, keyed by row key (already filtered to touched fields). */
  issues: Record<string, MemberRowIssues>
  onRowsChange: (rows: MemberDraft[]) => void
  /** Called with a field id (memberFieldId, or 'members') when one is touched. */
  onTouch: (fieldId: string) => void
  /** Locks every control, e.g. while the create request is in flight. */
  disabled?: boolean
}

export default function MemberRowsEditor({ kind, rows, issues, onRowsChange, onTouch, disabled = false }: Props) {
  const { t } = useI18n()
  const { user } = useAuth()
  const canSearchUsers = usePermission('users', 'view', user)

  if (!canSearchUsers) return <UserSearchGuidance />

  // ─── Row changes ───

  function changeRow(key: string, patch: Partial<MemberDraft>, field: MemberField) {
    onRowsChange(rows.map((row) => (row.key === key ? { ...row, ...patch } : row)))
    onTouch(memberFieldId(key, field))
  }

  function addRow() {
    onRowsChange([...rows, emptyMemberDraft(nextMemberKey(rows))])
  }

  function removeRow(key: string) {
    onRowsChange(rows.filter((row) => row.key !== key))
    onTouch('members')
  }

  return (
    <div className="stack">
      {rows.map((row, index) => (
        <MemberRow
          key={row.key}
          row={row}
          position={index + 1}
          kind={kind}
          issues={issues[row.key] ?? {}}
          disabled={disabled}
          onChange={(patch, field) => changeRow(row.key, patch, field)}
          onBlur={(field) => onTouch(memberFieldId(row.key, field))}
          onRemove={() => removeRow(row.key)}
        />
      ))}
      <div>
        <button type="button" className="secondary" onClick={addRow} disabled={disabled}>
          {t('chat_groups.create.add_member')}
        </button>
      </div>
    </div>
  )
}

// ─── One row ───

type RowProps = {
  row: MemberDraft
  /** 1-based position, used in the row's heading and its Remove label. */
  position: number
  kind: ChatGroupKind | null
  issues: MemberRowIssues
  disabled: boolean
  onChange: (patch: Partial<MemberDraft>, field: MemberField) => void
  onBlur: (field: MemberField) => void
  onRemove: () => void
}

/** One member's card: person, role, and (masked only) label. */
function MemberRow({ row, position, kind, issues, disabled, onChange, onBlur, onRemove }: RowProps) {
  const { t } = useI18n()
  const statusLabel = useStatusLabel()
  const id = useId()
  const heading = t('chat_groups.create.member_n', { n: position })
  const roleErrorId = `${id}-role-error`
  // Why a team row offers only two roles; shown under the select and named by
  // its aria-describedby, so it is read out with the field.
  const teamRolesNoteId = `${id}-role-team-note`
  const roleDescribedBy =
    [issues.role ? roleErrorId : '', kind === 'team' ? teamRolesNoteId : ''].filter(Boolean).join(' ') || undefined

  return (
    <div className="card stack" role="group" aria-label={heading}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 'var(--space-2)' }}>
        <strong>{heading}</strong>
        <button
          type="button"
          className="secondary"
          onClick={onRemove}
          disabled={disabled}
          aria-label={t('chat_groups.create.remove_member_aria', { n: position })}
        >
          {t('chat_groups.create.remove_member')}
        </button>
      </div>

      <div className="form-row">
        <span className="form-label">{t('chat_groups.create.person_label')}</span>
        <UserPicker value={row.user} onChange={(user) => onChange({ user }, 'user')} disabled={disabled} />
        <FieldNote id={`${id}-user-error`} issue={issues.user} />
      </div>

      <div className="form-grid">
        <div className="form-row field">
          <label className="form-label" htmlFor={`${id}-role`}>
            {t('chat_groups.create.role_label')}
          </label>
          <select
            id={`${id}-role`}
            value={row.role}
            disabled={disabled}
            aria-invalid={issues.role ? true : undefined}
            aria-describedby={roleDescribedBy}
            onChange={(e) => onChange({ role: isChatGroupRole(e.target.value) ? e.target.value : '' }, 'role')}
            onBlur={() => onBlur('role')}
          >
            <option value="">{t('chat_groups.create.role_placeholder')}</option>
            {rolesForKind(kind).map((role) => (
              <option key={role} value={role}>
                {statusLabel(role)}
              </option>
            ))}
          </select>
          {kind === 'team' && (
            <span id={teamRolesNoteId} className="form-hint">
              {t('chat_groups.create.team_roles_note')}
            </span>
          )}
          <FieldNote id={roleErrorId} issue={issues.role} />
        </div>

        {kind === 'masked' && (
          <LabelField
            id={id}
            value={row.label}
            issues={issues}
            disabled={disabled}
            onChange={(label) => onChange({ label }, 'label')}
            onBlur={() => onBlur('label')}
          />
        )}
      </div>
    </div>
  )
}

// ─── The masked label ───

type LabelFieldProps = {
  /** The row's base id; the field's ids are derived from it. */
  id: string
  value: string
  issues: MemberRowIssues
  disabled: boolean
  onChange: (label: string) => void
  onBlur: () => void
}

/**
 * The label other members see in place of this member's name. The standing
 * hint says a blank is fine; the contact hint appears, in the warning tone and
 * without blocking, when the label looks like a phone number or email.
 */
function LabelField({ id, value, issues, disabled, onChange, onBlur }: LabelFieldProps) {
  const { t } = useI18n()
  const inputId = `${id}-label`
  const hintId = `${id}-label-hint`
  const errorId = `${id}-label-error`
  const contactId = `${id}-label-contact`
  const describedBy = [hintId, issues.label ? errorId : '', issues.labelHint ? contactId : '']
    .filter(Boolean)
    .join(' ')

  return (
    <div className="form-row field">
      <label className="form-label" htmlFor={inputId}>
        {t('chat_groups.create.label_label')}
      </label>
      <input
        id={inputId}
        type="text"
        value={value}
        dir="auto"
        autoComplete="off"
        placeholder={t('chat_groups.create.label_placeholder')}
        disabled={disabled}
        aria-invalid={issues.label ? true : undefined}
        aria-describedby={describedBy}
        onChange={(e) => onChange(e.target.value)}
        onBlur={onBlur}
      />
      <span id={hintId} className="form-hint">
        {t('chat_groups.create.label_hint')}
      </span>
      <FieldNote id={errorId} issue={issues.label} />
      {issues.labelHint && (
        <span id={contactId} className="form-hint" style={{ color: 'var(--tone-warning-fg)' }}>
          {t(issues.labelHint.key)}
        </span>
      )}
    </div>
  )
}

// ─── Without users:view ───

/** Shown in place of the rows to staff who cannot search users (D2). Also used by AddMemberForm. */
export function UserSearchGuidance() {
  const { t } = useI18n()
  return (
    <div className="info-box stack" role="note">
      <strong>{t('chat_groups.create.no_user_search_title')}</strong>
      <p className="muted" style={{ margin: 0 }}>
        {t('chat_groups.create.no_user_search_body')}
      </p>
    </div>
  )
}
