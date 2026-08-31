// userEditFields — the Edit-User and New-User form definitions.
//
// WHY THIS FILE EXISTS (two reasons)
//
//  1. The owner's ask: "here when I open the edit screen, I should see all of
//     them as well, all of the things that he has entered". The form had 15
//     boxes against a profile of 104 columns, so almost everything a person had
//     entered was uneditable — staff could read a mistyped national ID on the
//     detail page and do nothing about it.
//
//  2. UsersPage.tsx was already ~700 lines. Growing it by another ninety field
//     declarations would put it far past the 500-line limit, so the field lists
//     moved out whole rather than being extended in place.
//
// The fields are DERIVED from lib/userProfileFields.ts — the same declaration
// the read-only page groups by — so a column cannot be visible on one surface
// and missing from the other. Only the account-level boxes (phone, username,
// password, role) and the handful of columns with a non-text control (gender's
// select, date_of_birth's date picker, the photo uploads) are written out by
// hand below.
//
// WHERE THE LATER PER-FIELD RULE CONTROL ATTACHES: not here. That control is a
// property of a field, so it belongs on the declaration in userProfileFields.ts
// and on ProfileFieldRow's rendering — this file would pick it up for free.

import type { FieldSpec } from '../components/EditModal'
import type { FieldRuleState } from './fieldRules'
import {
  USER_PROFILE_GROUPS,
  type ProfileField,
  type ProfileGroup,
} from './userProfileFields'

/** The gender values the app's own sign-up form offers. */
export const GENDER_OPTIONS = ['', 'Male', 'Female', 'Other']

/**
 * Columns the modal renders with something other than a plain text box.
 * Everything not listed here is a text input, which is what the column is:
 * `user_profiles` stores almost all of these as TEXT, including the counts —
 * so a `number` input would refuse values the app itself accepts.
 */
const CONTROL_OVERRIDES: Record<string, Partial<FieldSpec>> = {
  gender: { type: 'select', options: GENDER_OPTIONS },
  date_of_birth: { type: 'date' },
  family_size: { type: 'number' },
  // The sign-in-adjacent numbers get the phone cleaning EditModal applies for
  // `contact` strength: separators stripped, nothing else rewritten. NOT
  // 'login' — that strength is reserved for `users.phone`, the column sign-in
  // actually resolves accounts by.
  phone1: { phone: 'contact' },
  phone2: { phone: 'contact' },
  emergency_phone: { phone: 'contact' },
}

/** Turns one declared profile field into an EditModal FieldSpec. */
function toFieldSpec(field: ProfileField, group: ProfileGroup): FieldSpec | null {
  // A column the backend refuses to write has no business being a form box: an
  // identity code is assign-once, and a GPS coordinate is device-captured.
  if (!field.editable) return null

  const base: FieldSpec = {
    key: field.key,
    // `label` is EditModal's English fallback; `labelKey` is what actually
    // renders. fieldLabelFor's namespaces are tried in the same order the
    // read-only page uses, so the two screens print identical wording.
    label: field.key,
    labelKey: `dbfield.${field.key}`,
    type: 'text',
    section: group.titleKey,
  }
  if (field.kind === 'long') {
    return { ...base, type: 'textarea', rows: 2, full: true, ...CONTROL_OVERRIDES[field.key] }
  }
  if (field.kind === 'photo') {
    // crop:false — these are documents (an ID card, a house facade, a CV), and
    // cropping one is destroying evidence, not framing a portrait. The one
    // exception is the avatar, handled below.
    return {
      ...base,
      type: 'file',
      full: true,
      crop: field.key === 'profile_picture' ? 'square' : false,
    }
  }
  return { ...base, ...CONTROL_OVERRIDES[field.key] }
}

/** Every editable profile field, in the grouped order of the detail page. */
export const PROFILE_EDIT_FIELDS: FieldSpec[] = USER_PROFILE_GROUPS.flatMap((g) =>
  g.fields.map((f) => toFieldSpec(f, g)).filter((x): x is FieldSpec => x !== null),
)

/** The account-level boxes — not profile data, so declared by hand. */
const ACCOUNT_SECTION = 'profile.group.account'

/**
 * Edit User.
 *
 * Phone/password live at the account level; role, active and is_admin stay out
 * because they have their own dedicated /status endpoints (Phase 9 inline
 * dropdowns) and two ways to set one column is how they drift.
 */
export const USER_FIELDS: FieldSpec[] = [
  { key: 'phone', label: 'Phone', labelKey: 'field.phone', type: 'text', required: true, phone: 'login', section: ACCOUNT_SECTION },
  { key: 'email', label: 'Email', labelKey: 'field.email', type: 'text', section: ACCOUNT_SECTION },
  ...PROFILE_EDIT_FIELDS,
  {
    key: 'password',
    label: 'New password',
    labelKey: 'field.new_password',
    type: 'password',
    placeholder: 'Leave blank to keep unchanged',
    placeholderKey: 'hint.leave_blank_unchanged',
    full: true,
    section: ACCOUNT_SECTION,
  },
]

/**
 * New User.
 *
 * Same profile fields, plus the sign-in pair, gated per-field by Field Rules
 * under the `user_` prefix (migration 057) — the admin-only data-entry screen's
 * own rules, kept independent of the public sign-up form's.
 *
 * phone, role and the sign-in pair are never hidden by a rule: phone is the
 * required login identifier, role is an admin classification, and without a
 * username/password this window cannot produce an account that can sign in.
 */
export function buildNewUserFields(state: Record<string, FieldRuleState>): FieldSpec[] {
  const isRequired = (key: string) => state[key] === 'required'
  const isHidden = (key: string) => state[key] === 'hidden'
  const always = new Set(['phone', 'role', 'username', 'password'])

  const fields: FieldSpec[] = [
    { key: 'phone', label: 'Phone', labelKey: 'field.phone', type: 'text', required: true, phone: 'login', section: ACCOUNT_SECTION },
    { key: 'role', label: 'Role', labelKey: 'col.role', type: 'select', options: ['donor', 'beneficiary', 'volunteer', 'employee'], section: ACCOUNT_SECTION },
    { key: 'username', label: 'Username', labelKey: 'auth.username', type: 'text', placeholder: 'supervisor', section: ACCOUNT_SECTION },
    { key: 'password', label: 'Password', labelKey: 'auth.password', type: 'password', section: ACCOUNT_SECTION },
    { key: 'email', label: 'Email', labelKey: 'field.email', type: 'text', section: ACCOUNT_SECTION },
    ...PROFILE_EDIT_FIELDS.map((f) => ({ ...f, required: isRequired(f.key) })),
  ]
  return fields.filter((f) => always.has(f.key) || !isHidden(f.key))
}

/**
 * Flatten the {users + nested profile} row into the flat key/value object
 * EditModal expects.
 *
 * `profile` is a loose record because the list endpoint returns only the
 * thirteen legacy columns on it; the modal fills the rest from the detail
 * endpoint (see UsersPage's edit flow), and a key that is present in neither
 * simply starts empty.
 */
export function flattenForEdit(
  phone: string,
  profile: Record<string, unknown> | null | undefined,
): Record<string, unknown> {
  const out: Record<string, unknown> = { phone, password: '' }
  for (const f of USER_FIELDS) {
    if (f.key === 'phone' || f.key === 'password') continue
    const v = profile?.[f.key]
    out[f.key] = v === null || v === undefined ? '' : typeof v === 'string' ? v : String(v)
  }
  return out
}
