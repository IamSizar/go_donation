// FieldRuleCell — owner item #16, inside the user profile screen.
//
// "here when I open the edit screen, I should see all of them as well, all of
// the things that he has entered, and from here I can mark whats required,
// off, or optional". The dedicated Field Rules page already offered that; the
// owner confirmed they want it in BOTH places, so this is the same control —
// the same three states, posting to the same route — rendered one field at a
// time on the row that field already occupies.
//
// ─── THE DANGER THIS COMPONENT EXISTS TO CONTAIN ────────────────────────────
// The screen shows ONE person. The rule is per ROLE. Nothing in the schema is
// per-user: `registration_field_rules` has one row per field key, and a key is
// namespaced by role, not by account. So a dropdown sitting on Ali's record
// reading "Required" reads as "require this OF ALI" and in fact means "require
// this of every Volunteer, including the four thousand who registered last
// year".
//
// Two things stop a stray click from doing that:
//
//  1. THE LABEL NEVER SAYS "Required". It says "Required for all volunteers".
//     The scope is in the words the operator reads, not in a tooltip they may
//     never open.
//
//  2. NOTHING APPLIES UNTIL IT IS CONFIRMED. Choosing a state opens
//     askToConfirm() naming the role, the field and the change, in the
//     operator's own language; cancelling puts the dropdown back where it was.
//     A control that reconfigures registration for thousands of people on one
//     click is not a control, it is a trap.
//
// Existing users are never locked out by a change made here — the app PROMPTS
// them and lets them carry on (humanitarian/lib/modules/profile/
// required_fields_prompt.dart). That decision is the owner's, and it is what
// makes this control safe to hand to staff at all.

import { useState } from 'react'
import { describeError } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import type { FieldRuleState } from '../lib/fieldRules'
import { setFieldRuleState, type ColumnRule } from '../lib/fieldRuleColumns'

/**
 * i18n key for a role's PLURAL name — "all volunteers", not "volunteer". The
 * plural is the point: it is what tells the operator this is not about the
 * person on screen.
 */
function roleNameKey(roleId: number | undefined): string {
  switch (roleId) {
    case 1:
      return 'fieldrule.role.donors'
    case 2:
      return 'fieldrule.role.beneficiaries'
    case 3:
      return 'fieldrule.role.volunteers'
    default:
      return 'fieldrule.role.unknown'
  }
}

export default function FieldRuleCell({
  rule,
  roleId,
  fieldLabel,
  canEdit,
  onChanged,
}: {
  /** This column's rule for this role, from lib/fieldRuleColumns. */
  rule: ColumnRule
  roleId: number | undefined
  /** The field's already-translated name, for the confirmation sentence. */
  fieldLabel: string
  /**
   * Whether to offer the control at all. The SERVER is the authority (one
   * `fieldRuleWrite` gate in main.go); this only avoids inviting an operator
   * to press something that would be refused.
   */
  canEdit: boolean
  /** Re-read the rules after a successful write. */
  onChanged: () => void
}) {
  const { t } = useI18n()
  const toast = useToast()
  const [saving, setSaving] = useState(false)

  // A column no registration form asks for has no rule row to UPDATE, and
  // SetState would answer "Unknown field." Offering a control that can only
  // fail is worse than offering none.
  if (!rule.governed || !canEdit) return null

  const roleName = t(roleNameKey(roleId))

  async function choose(next: FieldRuleState) {
    if (next === rule.state) return
    const ok = await askToConfirm({
      title: t('fieldrule.confirm.title'),
      // The whole sentence — role, field, new state — because a confirmation
      // that only says "Are you sure?" confirms nothing. The second line says
      // what happens to people who already registered, which is the question
      // an operator would otherwise have to guess the answer to.
      message:
        t(`fieldrule.confirm.body.${next}`, { field: fieldLabel, role: roleName }) +
        '\n\n' +
        t('fieldrule.confirm.existing_users'),
      confirmLabel: t('fieldrule.confirm.apply'),
    })
    if (!ok) return
    setSaving(true)
    try {
      await setFieldRuleState(rule.ruleKey, next)
      toast.success(t('fieldrule.saved', { role: roleName }))
      onChanged()
    } catch (e) {
      // Never swallowed and never a raw status code: the operator is told what
      // failed, and the dropdown snaps back because `rule.state` is the only
      // source of truth for its value — nothing local was optimistically set.
      toast.error(describeError(e))
    } finally {
      setSaving(false)
    }
  }

  // ─── A THREE-STATE SEGMENTED CONTROL, NOT A DROPDOWN ─────────────────────
  // It replaced a <select> for two reasons the owner named:
  //
  //  1. DENSITY. This control repeats on ~90 rows of the profile page. A
  //     select is a full-height form box; three small buttons are a third of
  //     the height and read as one unit rather than as ninety form fields.
  //
  //  2. THE STATE IS VISIBLE WITHOUT OPENING ANYTHING. A closed select shows
  //     only the current value, so telling which of ninety fields are required
  //     meant reading ninety boxes one at a time. Here the whole scale is
  //     always on screen and the active segment is highlighted, so a section
  //     can be scanned in one pass.
  //
  // The safety properties are unchanged: the accessible name still carries the
  // role, and nothing applies until `choose` has been confirmed. The visible
  // segment labels are necessarily short — "Required", not "Required for all
  // volunteers" — so the ROLE is carried by the group's aria-label and, at the
  // moment it matters, by the confirmation sentence, which is the thing that
  // actually stands between a click and four thousand people.
  const STATES: FieldRuleState[] = ['required', 'optional', 'hidden']
  return (
    <div
      className="rule-seg"
      role="group"
      aria-label={t('fieldrule.control_label', { field: fieldLabel, role: roleName })}
    >
      {STATES.map((state) => (
        <button
          key={state}
          type="button"
          className="rule-seg-btn"
          // aria-pressed rather than a visual class alone: a screen reader has
          // to be able to tell which of the three is active too.
          aria-pressed={rule.state === state}
          data-active={rule.state === state ? '' : undefined}
          data-state={state}
          disabled={saving}
          // The full, role-naming sentence on hover/focus — the wording the
          // select used to show in its options.
          title={t(`fieldrule.scope.${state}`, { role: roleName })}
          onClick={() => void choose(state)}
        >
          {t(`fieldrule.short.${state}`)}
        </button>
      ))}
    </div>
  )
}
