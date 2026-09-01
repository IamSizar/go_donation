// userProfileFields — the one declaration of what a user account HOLDS, which
// role was ever ASKED for it, and how it should be rendered.
//
// WHY THIS FILE EXISTS
// The owner's report was "I want all the data and the fields and photos and
// docs and every single thing that the user added to appear here". The detail
// page showed a "—" for almost all of it, because the API only ever sent 13 of
// `user_profiles`' 104 user-entered columns. Now that the API sends them all
// (backend/internal/handlers/admin_detail_user_profile.go), 104 rows in one
// alphabetical wall would be a different kind of unreadable — so the layout is
// declared here, once, and used by BOTH surfaces:
//
//   • components/UserProfileSections.tsx — the read-only عرض page
//   • lib/userEditFields.ts              — the Edit modal's field list
//
// so a column can never appear on one and be forgotten on the other.
//
// ─── "EMPTY" AND "NOT COLLECTED" ARE DIFFERENT THINGS ───────────────────────
// This is the distinction that produced the owner's report. The old screen
// printed the same bare "—" whether the person had left a box blank or had
// never been shown that box at all, so a Grantor's account looked like a
// half-broken Recipient's. `roles` below is what tells the two apart.
//
// WHERE `roles` COMES FROM. It is not invented here. It is the set of roles
// whose registration form asks for the column, read off `registration_field_
// rules` — the table the app's sign-up forms are actually driven by:
//
//   SELECT field_key FROM registration_field_rules
//    WHERE field_key LIKE 'grantor_%'    -- role 1, Donor / Grantor
//       OR field_key LIKE 'recipient_%'  -- role 2, Beneficiary / Recipient
//       OR field_key LIKE 'volunteer_%'; -- role 3, Volunteer
//
// with the handful of keys whose name differs from the column they fill
// expanded (`name_parts` → the four name columns, `gps_location` → gps_lat and
// gps_lng, `*_photo` → `*_photo_path`, `personal_photo` → profile_picture).
// Unprefixed keys are the app's shared sign-up form, asked of every role.
//
// It WAS a static snapshot on purpose, pending the required/optional/off
// control. That control now exists (owner #15/#16), so the live rules table is
// read at render time by lib/fieldRuleColumns.ts and passed to
// isCollectedForRole below, which prefers it. The snapshot survives as the
// fallback for the three moments there is no live answer — still loading, the
// fetch failed, or a caller with no rules context — because it was correct on
// the day it was written and "unknown" would be a worse thing to render.
//
// ─── ADDING A COLUMN LATER ──────────────────────────────────────────────────
// Add it to the right group below and to the backend allow-list. The backend
// test TestUserProfileDetailListMatchesTheSchema fails if a migration adds a
// profile column that nobody has decided about.

/** A user's role id, as stored in `users.role_id`. */
export const ROLE_DONOR = 1
export const ROLE_BENEFICIARY = 2
export const ROLE_VOLUNTEER = 3

/** How a value should be rendered and, in the modal, edited. */
export type ProfileFieldKind =
  | 'text' // a short free-text value
  | 'long' // a paragraph — textarea in the modal, full width on the page
  | 'photo' // an upload path: shown as a thumbnail, opened full size on click
  | 'coord' // a GPS number; shown, never edited by hand (see the backend note)
  | 'code' // a server-assigned identity code; shown, never edited

/** One column of `user_profiles` as the dashboard treats it. */
export type ProfileField = {
  /** The column name — also the i18n lookup key and the JSON key. */
  key: string
  kind: ProfileFieldKind
  /**
   * The roles whose registration form asks for this column. A value is
   * "blank" for a role in this list and "not collected" for one that is not.
   */
  roles: number[]
  /**
   * Editable from the dashboard's Edit modal. False for the columns the
   * backend refuses to write (identity codes, coordinates) — see
   * backend/internal/handlers/admin_edit_user_profile.go for why each one.
   */
  editable: boolean
}

/** A titled block of fields on the detail page and in the Edit modal. */
export type ProfileGroup = {
  /** i18n key for the section heading. */
  titleKey: string
  fields: ProfileField[]
}

const ALL: number[] = [ROLE_DONOR, ROLE_BENEFICIARY, ROLE_VOLUNTEER]
const BENE_VOL: number[] = [ROLE_BENEFICIARY, ROLE_VOLUNTEER]
const BENE: number[] = [ROLE_BENEFICIARY]
const VOL: number[] = [ROLE_VOLUNTEER]

/** Shorthand so the tables below read as data rather than as object literals. */
const f = (
  key: string,
  roles: number[],
  kind: ProfileFieldKind = 'text',
  editable = true,
): ProfileField => ({ key, kind, roles, editable })

// ─── The layout ─────────────────────────────────────────────────────────────
// Groups are in the order the registration forms ask the questions, so the page
// reads like the form the person filled in.
export const USER_PROFILE_GROUPS: ProfileGroup[] = [
  {
    titleKey: 'profile.group.identity',
    fields: [
      f('full_name', ALL),
      f('name_first', ALL),
      f('name_father', ALL),
      f('name_grandfather', ALL),
      f('name_family', ALL),
      f('title_surname', ALL),
      f('alias_name', ALL),
      f('national_id', ALL),
      f('date_of_birth', ALL),
      f('gender', ALL),
      f('nationality', BENE_VOL),
      f('tribe_clan', BENE_VOL),
      f('marital_status', BENE_VOL),
      f('residency_status', BENE),
      f('languages', VOL),
      // Assign-once codes minted by the server, one per role.
      f('grantor_code', [ROLE_DONOR], 'code', false),
      f('recipient_code', BENE, 'code', false),
      f('volunteer_code', VOL, 'code', false),
    ],
  },
  {
    titleKey: 'profile.group.contact',
    fields: [
      f('phone1', ALL),
      f('phone2', ALL),
      f('emergency_phone', BENE_VOL),
      f('email', ALL),
      f('social_facebook', BENE_VOL),
      f('social_instagram', BENE_VOL),
      f('social_telegram', BENE_VOL),
      f('social_other', VOL),
    ],
  },
  {
    titleKey: 'profile.group.location',
    fields: [
      f('governorate', ALL),
      f('district', VOL),
      f('city', ALL),
      f('housing_side', BENE_VOL),
      f('neighborhood', BENE_VOL),
      f('address', ALL, 'long'),
      f('nearest_landmark', BENE_VOL),
      // Captured by the phone's GPS; shown, not hand-typed.
      f('gps_lat', ALL, 'coord', false),
      f('gps_lng', ALL, 'coord', false),
    ],
  },
  {
    titleKey: 'profile.group.housing',
    fields: [
      f('housing_status', ALL),
      f('housing_type', BENE_VOL),
      f('rental_amount', BENE),
      f('housing_area', BENE_VOL),
      f('floors_count', BENE),
      f('rooms_count', BENE),
      f('families_count', BENE),
      f('available_furniture', BENE, 'long'),
      f('owns_car', BENE),
    ],
  },
  {
    titleKey: 'profile.group.work',
    fields: [
      f('is_employed', BENE),
      f('workplace', BENE),
      f('occupation', ALL),
      f('previous_occupation', BENE_VOL),
      f('job_description', BENE, 'long'),
      f('working_hours', BENE),
      f('wage_amount', BENE),
      f('monthly_income', ALL),
      f('registered_social_welfare', BENE),
      f('registered_unemployed', BENE),
      f('household_employees_count', BENE),
      f('working_members_count', BENE),
    ],
  },
  {
    titleKey: 'profile.group.education',
    fields: [
      f('education_level', ALL),
      f('other_certificate', BENE_VOL),
      f('certificates_count', BENE),
    ],
  },
  {
    titleKey: 'profile.group.household',
    fields: [
      f('family_size', ALL),
      f('men_count', BENE),
      f('women_count', BENE),
      f('male_children_count', BENE),
      f('female_children_count', BENE),
      f('age_0_5_count', BENE),
      f('age_5_10_count', BENE),
      f('age_10_15_count', BENE),
      f('age_15_25_count', BENE),
      f('age_25_40_count', BENE),
      f('age_40_plus_count', BENE),
      f('students_count', BENE),
      f('orphans_count', BENE),
      f('widows_count', BENE),
      f('divorced_count', BENE),
      f('household_disabled_count', BENE),
    ],
  },
  {
    titleKey: 'profile.group.health',
    fields: [
      f('height', BENE),
      f('weight', BENE),
      f('smoking_status', BENE),
      f('eyesight_condition', BENE),
      f('has_disability', BENE),
      f('disability_type', BENE),
      f('chronic_illnesses', BENE, 'long'),
      f('medical_conditions_count', BENE),
      f('medical_conditions_desc', BENE, 'long'),
    ],
  },
  {
    titleKey: 'profile.group.volunteering',
    fields: [f('skills', ALL, 'long'), f('availability', ALL), f('experience', ALL, 'long')],
  },
  {
    titleKey: 'profile.group.needs',
    fields: [
      f('needs_description', BENE, 'long'),
      f('consent_show_real_name', BENE),
      f('consent_share_info', BENE),
    ],
  },
  {
    titleKey: 'profile.group.documents',
    fields: [
      f('profile_picture', ALL, 'photo'),
      f('id_photo_path', ALL, 'photo'),
      f('ration_card_photo_path', BENE_VOL, 'photo'),
      f('residence_card_photo_path', VOL, 'photo'),
      f('passport_photo_path', VOL, 'photo'),
      f('golden_square_photo_path', VOL, 'photo'),
      f('graduation_cert_photo_path', VOL, 'photo'),
      f('cv_photo_path', VOL, 'photo'),
      f('property_proof_photo_path', BENE, 'photo'),
      f('medical_report_photo_path', BENE, 'photo'),
      f('house_facade_photo_path', BENE, 'photo'),
      f('house_inside_photo_path', BENE, 'photo'),
      f('house_outside_photo_path', BENE, 'photo'),
    ],
  },
]

/** Every declared field, flattened — useful for lookups by key. */
export const USER_PROFILE_FIELDS: ProfileField[] = USER_PROFILE_GROUPS.flatMap((g) => g.fields)

/** key → field, so a renderer can ask about one column in O(1). */
export const USER_PROFILE_FIELD_BY_KEY: Record<string, ProfileField> = Object.fromEntries(
  USER_PROFILE_FIELDS.map((x) => [x.key, x]),
)

/**
 * Whether this account's role was ever ASKED for this column.
 *
 * An unknown role (0 / none / employee / a marriage account) answers true: the
 * honest reading of "we have no form for this role" is "we cannot say this was
 * never collected", and claiming otherwise would print a confident falsehood.
 */
// Owner #15 — `liveRules`, when supplied, is the answer read off
// `registration_field_rules` at render time (lib/fieldRuleColumns.ts). It
// SUPERSEDES the static `roles` list above, which the file header always
// described as a snapshot pending exactly this change: staff can now switch a
// field on for a role from the dashboard, and the detail page must stop
// calling it "not collected" the moment they do.
//
// The snapshot remains the fallback for the three cases where there is no live
// answer: the rules are still loading, the fetch failed, or the caller is one
// that has no rules context. Falling back to it is strictly better than
// falling back to "unknown", because it was correct on the day it was written.
export function isCollectedForRole(
  key: string,
  roleId: number | undefined,
  liveRules?: Record<string, { governed: boolean; state: string }>,
): boolean {
  const field = USER_PROFILE_FIELD_BY_KEY[key]
  if (!field) return true
  if (roleId !== ROLE_DONOR && roleId !== ROLE_BENEFICIARY && roleId !== ROLE_VOLUNTEER) return true
  if (liveRules) {
    const rule = liveRules[key]
    // A field switched OFF for this role is not collected either — that is
    // what "off" means, and it is the same reading the app's form applies.
    if (rule) return rule.governed && rule.state !== 'hidden'
    return false
  }
  return field.roles.includes(roleId)
}

/**
 * The `field_privacy` key that governs a column, or null when the app offers no
 * switch for it.
 *
 * The catalogue is `privacy_field_options` (migration 083) and its keys are not
 * always the column name — `phone` covers the phone columns, `address` covers
 * the street address. Only the ten catalogue entries exist; every other column
 * simply has no switch, which is not the same as "the user chose to share it"
 * and is rendered as neither.
 */
export function privacyKeyFor(column: string): string | null {
  switch (column) {
    case 'full_name':
      return 'full_name'
    case 'phone':
    case 'phone1':
    case 'phone2':
      return 'phone'
    case 'gender':
      return 'gender'
    case 'address':
      return 'address'
    case 'date_of_birth':
      return 'date_of_birth'
    case 'profile_picture':
      return 'profile_picture'
    case 'education_level':
      return 'education_level'
    case 'occupation':
      return 'occupation'
    case 'governorate':
      return 'governorate'
    default:
      return null
  }
}
