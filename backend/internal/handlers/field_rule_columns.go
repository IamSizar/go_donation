// field_rule_columns.go — the one translation between a `registration_field_
// rules` KEY and the `user_profiles` COLUMN(s) it governs.
//
// WHY THIS FILE EXISTS
// The rules table names fields the way the app's registration FORM asks for
// them, which is not always the way the database stores them:
//
//	volunteer_name_parts   → one form section, FOUR columns
//	recipient_gps_location → one "share my location" control, TWO columns
//	grantor_personal_photo → stored as profile_picture
//	recipient_id_photo     → stored as id_photo_path
//	recipient_working_members → stored as working_members_count
//
// Until now that translation existed only as a hand-copied comment in
// admin-web/src/lib/userProfileFields.ts ("a static snapshot ON PURPOSE").
// Owner items #15/#16 need the dashboard's own create/edit form to obey the
// same rules the app already obeys, and a form cannot obey a rule it cannot
// map onto a column — so the mapping becomes real code, on the server, where
// it can be ENFORCED rather than merely rendered. admin-web/src/lib/
// fieldRuleColumns.ts is the client-side twin of this file; the two are kept
// identical by TestFieldRuleColumnMapCoversEveryRoleKey (this package) and by
// the dashboard build, and either alone is only a UX nicety — this one is the
// authority.
package handlers

import (
	"context"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Rule-key prefixes. Every seeded key either starts with one of these or is
// one of the handful of UNPREFIXED keys that the app's shared sign-up step
// asks of every role (gender, city, date_of_birth, …).
const (
	fieldRulePrefixGrantor   = "grantor_"
	fieldRulePrefixRecipient = "recipient_"
	fieldRulePrefixVolunteer = "volunteer_"
	// Not roles: the Marriage module, the Beneficiary case form, and the
	// dashboard's own New-User window each own a namespace of their own.
	fieldRulePrefixMarriage = "marriage_"
	fieldRulePrefixCase     = "case_"
	fieldRulePrefixNewUser  = "user_"
)

// allFieldRulePrefixes — used only to recognise a key as prefixed at all, so
// that "not prefixed" can be read as "asked of every role".
var allFieldRulePrefixes = []string{
	fieldRulePrefixGrantor, fieldRulePrefixRecipient, fieldRulePrefixVolunteer,
	fieldRulePrefixMarriage, fieldRulePrefixCase, fieldRulePrefixNewUser,
}

// fieldRulePrefixForRole maps `users.role_id` to the namespace whose rules
// govern that account's registration form.
//
// A role that is not one of the three app roles (0/NULL, or a staff account)
// returns "" and is deliberately NOT governed: there is no registration form
// behind those accounts, so there is no rule that could be said to apply, and
// inventing one would block staff from editing their own colleagues' rows.
func fieldRulePrefixForRole(roleID int) string {
	switch roleID {
	case 1:
		return fieldRulePrefixGrantor
	case 2:
		return fieldRulePrefixRecipient
	case 3:
		return fieldRulePrefixVolunteer
	default:
		return ""
	}
}

// fieldRuleKeySuffix strips whichever namespace prefix a key carries. An
// unprefixed key is returned unchanged.
func fieldRuleKeySuffix(key string) string {
	for _, p := range allFieldRulePrefixes {
		if strings.HasPrefix(key, p) {
			return strings.TrimPrefix(key, p)
		}
	}
	return key
}

// fieldRuleSuffixColumns — the suffixes whose column name is NOT simply the
// suffix. Everything absent from this map either follows the `_photo` →
// `_photo_path` rule below or is already the column name.
//
// These are not guesses: each was verified against
// information_schema.columns for `user_profiles` (see
// TestFieldRuleColumnMapResolvesEveryRoleKey, which fails on any key this
// file cannot place).
var fieldRuleSuffixColumns = map[string][]string{
	// One "your full name" section on the form, four stored parts.
	"name_parts": {"name_first", "name_father", "name_grandfather", "name_family"},
	// One "share my location" control, one coordinate pair.
	"gps_location": {"gps_lat", "gps_lng"},
	// The avatar is asked for as a "personal photo" and stored as the account
	// picture — the same column the app's own profile screen writes.
	"personal_photo": {"profile_picture"},
	// Three household counts whose form key dropped the `_count` suffix.
	"household_disabled":  {"household_disabled_count"},
	"household_employees": {"household_employees_count"},
	"working_members":     {"working_members_count"},
}

// fieldRuleColumns returns the `user_profiles` column(s) one rule key governs.
// Never nil for a well-formed key: the fallback is the key's own suffix, which
// is the convention every ordinary field follows.
func fieldRuleColumns(key string) []string {
	suffix := fieldRuleKeySuffix(key)
	if cols, ok := fieldRuleSuffixColumns[suffix]; ok {
		return cols
	}
	// An attachment is asked for as `<thing>_photo` and stored at
	// `<thing>_photo_path` — the path the upload endpoint hands back.
	if strings.HasSuffix(suffix, "_photo") {
		return []string{suffix + "_path"}
	}
	return []string{suffix}
}

// fieldRuleColumnStates loads the rules that govern one namespace and flattens
// them onto the columns they control: column name → "required"|"optional"|
// "hidden".
//
// includeShared adds the unprefixed keys — the shared sign-up step every role
// passes through. The New-User window (`user_` prefix) sets it false because
// that namespace already carries its own copy of each shared field
// (migration 057), and reading both would let two rows disagree about one box.
//
// A key whose columns collide with another key's (none do today, but
// `name_parts` shows how one could) resolves to the STRICTER state, in the
// order hidden > required > optional: never render a field somebody switched
// off, and never silently drop a requirement.
func fieldRuleColumnStates(ctx context.Context, pool *pgxpool.Pool, prefix string, includeShared bool) (map[string]string, error) {
	rows, err := pool.Query(ctx, `SELECT field_key, state FROM registration_field_rules`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	rank := map[string]int{"optional": 0, "required": 1, "hidden": 2}
	out := map[string]string{}
	for rows.Next() {
		var key, state string
		if err := rows.Scan(&key, &state); err != nil {
			return nil, err
		}
		switch {
		case prefix != "" && strings.HasPrefix(key, prefix):
			// governed
		case includeShared && !hasAnyFieldRulePrefix(key):
			// the shared sign-up step
		default:
			continue
		}
		for _, col := range fieldRuleColumns(key) {
			if cur, ok := out[col]; !ok || rank[state] > rank[cur] {
				out[col] = state
			}
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

// hasAnyFieldRulePrefix reports whether a key belongs to a named namespace.
func hasAnyFieldRulePrefix(key string) bool {
	for _, p := range allFieldRulePrefixes {
		if strings.HasPrefix(key, p) {
			return true
		}
	}
	return false
}
