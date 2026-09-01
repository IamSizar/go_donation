// fieldRuleColumns — owner items #15 and #16.
//
// #15 is "the dashboard form must match the app". The app's registration forms
// have been driven by `registration_field_rules` since #43; the dashboard's
// own create/edit form was a hand-maintained list, which is exactly why the
// two drifted. This module is the join between them: it turns a rule KEY into
// the `user_profiles` COLUMN(s) it governs, so a dashboard box can ask "am I
// required for this role?" and get the same answer the app's box gets.
//
// WHY THE MAPPING IS NOT THE IDENTITY FUNCTION
// The rules name fields as the FORM asks for them; the profile stores them as
// COLUMNS, and the two disagree in five documented shapes (name_parts,
// gps_location, personal_photo, `*_photo`, and three counts whose form key
// dropped `_count`). Every one of them is a live row today.
//
// THIS FILE IS THE CLIENT TWIN OF backend/internal/handlers/field_rule_
// columns.go. The server is the AUTHORITY — it refuses a blank required field
// and a switched-off one whatever this file believes. What this file buys is
// the UX half: an asterisk before the operator presses Save, instead of a 400
// after. They are kept in step by TestFieldRuleColumnStatesResolvesEveryRoleKey
// on the Go side, which fails if a seeded key maps to no real column.
//
// It also RETIRES the static `roles` snapshot in userProfileFields.ts. That
// file's own header says reading the rules live is the follow-up; this is it.

import { useEffect, useState } from 'react'
import { api } from './api'
import type { FieldRuleState } from './fieldRules'

/** A user's role id, as stored in `users.role_id`. */
export const ROLE_DONOR = 1
export const ROLE_BENEFICIARY = 2
export const ROLE_VOLUNTEER = 3

/**
 * Rule-key namespaces. A key either starts with one of these or is one of the
 * handful of UNPREFIXED keys the app's shared sign-up step asks of every role.
 */
export const FIELD_RULE_PREFIXES = [
  'grantor_',
  'recipient_',
  'volunteer_',
  'marriage_',
  'case_',
  'user_',
] as const

/**
 * The namespace whose rules govern one role's registration form.
 *
 * Returns null for anything that is not one of the three app roles (a staff
 * account, or a row whose role was never set): there is no registration form
 * behind those accounts, so no rule can be said to apply to them. Mirrors
 * fieldRulePrefixForRole in the Go twin exactly.
 */
export function rulePrefixForRole(roleId: number | undefined): string | null {
  switch (roleId) {
    case ROLE_DONOR:
      return 'grantor_'
    case ROLE_BENEFICIARY:
      return 'recipient_'
    case ROLE_VOLUNTEER:
      return 'volunteer_'
    default:
      return null
  }
}

/** Strips whichever namespace prefix a key carries; unprefixed keys pass through. */
export function ruleKeySuffix(key: string): string {
  const p = FIELD_RULE_PREFIXES.find((prefix) => key.startsWith(prefix))
  return p ? key.slice(p.length) : key
}

/**
 * The suffixes whose column name is NOT simply the suffix. Verified against
 * `information_schema.columns` for `user_profiles`; see the Go twin, whose
 * test fails on any seeded key that cannot be placed.
 */
const IRREGULAR_SUFFIX_COLUMNS: Record<string, string[]> = {
  // One "your full name" section on the form, four stored parts.
  name_parts: ['name_first', 'name_father', 'name_grandfather', 'name_family'],
  // One "share my location" control, one coordinate pair.
  gps_location: ['gps_lat', 'gps_lng'],
  // Asked for as a "personal photo", stored as the account picture.
  personal_photo: ['profile_picture'],
  // Three household counts whose form key dropped the `_count` suffix.
  household_disabled: ['household_disabled_count'],
  household_employees: ['household_employees_count'],
  working_members: ['working_members_count'],
}

/** The `user_profiles` column(s) one rule key governs. */
export function columnsForRuleKey(key: string): string[] {
  const suffix = ruleKeySuffix(key)
  const irregular = IRREGULAR_SUFFIX_COLUMNS[suffix]
  if (irregular) return irregular
  // An attachment is asked for as `<thing>_photo` and stored at
  // `<thing>_photo_path` — the path the upload endpoint hands back.
  if (suffix.endsWith('_photo')) return [`${suffix}_path`]
  return [suffix]
}

/** One row of the admin field-rules endpoint. */
export type FieldRuleRow = { field_key: string; state: FieldRuleState; display_order: number }

/**
 * What a form needs to know about one column, for one role.
 *
 * `ruleKey` is carried so the in-row control (UserProfileSections) knows which
 * rule to POST, and `governed` says whether this role's registration form asks
 * for the column AT ALL — which is what replaces the old static `roles` list.
 */
export type ColumnRule = {
  state: FieldRuleState
  ruleKey: string
  governed: boolean
}

/** The answer for a column nobody's form asks for: shown, never enforced. */
const UNGOVERNED: ColumnRule = { state: 'optional', ruleKey: '', governed: false }

/**
 * Resolves one role's rules onto columns.
 *
 * Two rules can land on the same column (none do today, but `name_parts`
 * shows how one could). The STRICTER wins, in the order hidden > required >
 * optional — never render a field somebody switched off, and never silently
 * drop a requirement. Same precedence as the Go twin.
 */
const STRICTNESS: Record<FieldRuleState, number> = { optional: 0, required: 1, hidden: 2 }

export function columnRulesForRole(rows: FieldRuleRow[], roleId: number | undefined): Record<string, ColumnRule> {
  const prefix = rulePrefixForRole(roleId)
  const out: Record<string, ColumnRule> = {}
  for (const row of rows) {
    const prefixed = FIELD_RULE_PREFIXES.some((p) => row.field_key.startsWith(p))
    // A key belongs to this role if it is in the role's own namespace, or is
    // unprefixed — the shared sign-up step every role passes through.
    const applies = (prefix !== null && row.field_key.startsWith(prefix)) || !prefixed
    if (!applies) continue
    for (const col of columnsForRuleKey(row.field_key)) {
      const cur = out[col]
      if (!cur || STRICTNESS[row.state] > STRICTNESS[cur.state]) {
        out[col] = { state: row.state, ruleKey: row.field_key, governed: true }
      }
    }
  }
  return out
}

/**
 * Fetches every rule once and hands back a per-role resolver.
 *
 * All four async states are the caller's to render; this reports `loading` and
 * `error` and never throws. On a FAILED fetch the resolver answers "ungoverned"
 * for everything — the pre-#15 behaviour, i.e. every box shown and none
 * required. That is the right failure: the server still refuses a genuinely
 * bad save, so a wrongly-lenient form costs a round trip, whereas a wrongly-
 * strict one would make an account uneditable because a config fetch blipped.
 */
export function useUserFieldRules(): {
  rows: FieldRuleRow[]
  loading: boolean
  error: string | null
  reload: () => void
  rulesFor: (roleId: number | undefined) => Record<string, ColumnRule>
  ruleFor: (column: string, roleId: number | undefined) => ColumnRule
} {
  const [rows, setRows] = useState<FieldRuleRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [tick, setTick] = useState(0)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    api
      .get<{ items: FieldRuleRow[] }>('/api/admin/registration/field-rules')
      .then((r) => {
        if (cancelled) return
        setRows(r.data.items ?? [])
        setError(null)
      })
      .catch((e: unknown) => {
        if (cancelled) return
        // NOT swallowed: recorded so the caller can say so, and the resolver
        // degrades to "nothing required, nothing hidden" (see above).
        setRows([])
        setError(e instanceof Error ? e.message : String(e))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [tick])

  const rulesFor = (roleId: number | undefined) => columnRulesForRole(rows, roleId)
  const ruleFor = (column: string, roleId: number | undefined) =>
    columnRulesForRole(rows, roleId)[column] ?? UNGOVERNED

  return { rows, loading, error, reload: () => setTick((n) => n + 1), rulesFor, ruleFor }
}

/**
 * Writes one rule. Role-wide by construction — there is no per-user rule
 * anywhere in the schema — which is why every caller must confirm first.
 *
 * Posts to the SAME route the dedicated Field Rules page uses, so the single
 * authorization gate on the server (main.go's `fieldRuleWrite`) governs both
 * surfaces and a future ARBAC permission replaces the tier check in one place.
 */
export async function setFieldRuleState(ruleKey: string, state: FieldRuleState): Promise<void> {
  await api.post(`/api/admin/registration/field-rules/${encodeURIComponent(ruleKey)}`, { state })
}
