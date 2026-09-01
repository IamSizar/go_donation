// field_rule_enforcement_test.go — owner #15/#16.
//
// Two of these tests need no database: the key→column mapping and the
// blank/present logic are pure. The rest drive the real
// `registration_field_rules` table through the real statements, because the
// claim under test is "the SERVER refuses it", and a refusal computed against
// a fixture proves nothing about the rows staff actually edit.
//
//	createdb godonation_fr           # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_fr?sslmode=disable' \
//	  go test ./internal/handlers/ -run FieldRule -v
package handlers

import (
	"context"
	"encoding/json"
	"testing"
)

// ─── The mapping (no database) ──────────────────────────────────────────────

// TestFieldRuleColumnsResolvesTheIrregularKeys pins the five shapes that are
// NOT "the key is the column name". Every one of them was a real row in the
// live table; getting any of them wrong silently un-governs a field, which
// looks exactly like the feature working.
func TestFieldRuleColumnsResolvesTheIrregularKeys(t *testing.T) {
	cases := map[string][]string{
		"volunteer_name_parts":      {"name_first", "name_father", "name_grandfather", "name_family"},
		"recipient_gps_location":    {"gps_lat", "gps_lng"},
		"grantor_personal_photo":    {"profile_picture"},
		"recipient_id_photo":        {"id_photo_path"},
		"recipient_working_members": {"working_members_count"},
		// The ordinary case, and the unprefixed shared one.
		"volunteer_national_id": {"national_id"},
		"gender":                {"gender"},
	}
	for key, want := range cases {
		got := fieldRuleColumns(key)
		if len(got) != len(want) {
			t.Errorf("%s → %v, want %v", key, got, want)
			continue
		}
		for i := range want {
			if got[i] != want[i] {
				t.Errorf("%s → %v, want %v", key, got, want)
				break
			}
		}
	}
}

// TestFieldRulePrefixForRoleLeavesStaffUngoverned. A staff account has no
// registration form, so no rule can apply to it; if this ever returned a
// prefix, editing a colleague's row would start failing on a Beneficiary's
// requirements.
func TestFieldRulePrefixForRoleLeavesStaffUngoverned(t *testing.T) {
	for role, want := range map[int]string{
		1: "grantor_", 2: "recipient_", 3: "volunteer_",
		0: "", 4: "", -1: "",
	} {
		if got := fieldRulePrefixForRole(role); got != want {
			t.Errorf("role %d → %q, want %q", role, got, want)
		}
	}
}

// TestIsBlankJSONValueKeepsZeroAndFalse. `0` and `false` are answers, not
// omissions — refusing them would make "family_size: 0" unsavable on a role
// where family_size is required.
func TestIsBlankJSONValueKeepsZeroAndFalse(t *testing.T) {
	blank := []string{`""`, `"   "`, `null`}
	notBlank := []string{`0`, `false`, `"0"`, `"x"`}
	for _, s := range blank {
		if !isBlankJSONValue(json.RawMessage(s)) {
			t.Errorf("%s should be blank", s)
		}
	}
	for _, s := range notBlank {
		if isBlankJSONValue(json.RawMessage(s)) {
			t.Errorf("%s should NOT be blank", s)
		}
	}
}

// ─── The enforcement, against the real table ────────────────────────────────

// setRuleState flips one rule for the duration of a test and puts it back,
// so a run leaves the table exactly as it found it.
func setRuleState(t *testing.T, ctx context.Context, key, state string) {
	t.Helper()
	pool := newFieldRulesTestPool(t)
	var original string
	if err := pool.QueryRow(ctx,
		`SELECT state FROM registration_field_rules WHERE field_key = $1`, key).Scan(&original); err != nil {
		t.Fatalf("%s is not seeded: %v", key, err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE registration_field_rules SET state = $2 WHERE field_key = $1`, key, state); err != nil {
		t.Fatalf("set %s = %s: %v", key, state, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`UPDATE registration_field_rules SET state = $2 WHERE field_key = $1`, key, original)
	})
}

// TestFieldRuleRequiredIsEnforcedServerSide — the headline claim of #15. A
// dashboard that renders an asterisk is UX; this is the rule.
func TestFieldRuleRequiredIsEnforcedServerSide(t *testing.T) {
	pool := newFieldRulesTestPool(t)
	ctx := context.Background()
	setRuleState(t, ctx, "volunteer_national_id", "required")

	// The form submitted with the box left empty.
	v, err := checkFieldRules(ctx, pool, fieldRulePrefixVolunteer, true,
		[]byte(`{"phone":"07700000000","national_id":""}`))
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if v == nil || v.Column != "national_id" || v.Code != "field_required_by_rule" {
		t.Fatalf("a blank required field was accepted: %+v", v)
	}

	// Filled in — accepted.
	v, err = checkFieldRules(ctx, pool, fieldRulePrefixVolunteer, true,
		[]byte(`{"national_id":"19900101"}`))
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if v != nil {
		t.Fatalf("a filled required field was refused: %+v", v)
	}

	// Not mentioned at all — accepted. This is what keeps an account
	// registered before the rule existed editable: PATCH is a partial update,
	// and existing users are never held hostage by a new requirement.
	v, err = checkFieldRules(ctx, pool, fieldRulePrefixVolunteer, true, []byte(`{"phone":"07700000000"}`))
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if v != nil {
		t.Fatalf("an absent required field was refused: %+v", v)
	}
}

// TestFieldRuleHiddenIsNotAcceptedIfInjected — the other half of #15. The
// dashboard form does not render a hidden field; nothing stops another client
// from posting one anyway, so the server refuses it.
func TestFieldRuleHiddenIsNotAcceptedIfInjected(t *testing.T) {
	pool := newFieldRulesTestPool(t)
	ctx := context.Background()
	setRuleState(t, ctx, "volunteer_languages", "hidden")

	v, err := checkFieldRules(ctx, pool, fieldRulePrefixVolunteer, true,
		[]byte(`{"languages":"Kurdish"}`))
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if v == nil || v.Column != "languages" || v.Code != "field_hidden_by_rule" {
		t.Fatalf("a switched-off field was written: %+v", v)
	}

	// A blank is NOT refused: an honest client that simply did not render the
	// box may still post an empty string for it, and punishing that would
	// break the form for the sake of nothing.
	v, err = checkFieldRules(ctx, pool, fieldRulePrefixVolunteer, true, []byte(`{"languages":""}`))
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if v != nil {
		t.Fatalf("a blank hidden field was refused: %+v", v)
	}
}

// TestFieldRuleIsPerRoleNotPerUser — the risk the whole edit-screen control
// carries, pinned as behaviour: a rule set while looking at ONE Volunteer's
// record governs the NEXT Volunteer too, and does not touch a Grantor.
//
// This is asserted at the level the rule actually lives at (the role's
// namespace) rather than by creating two user rows, because that IS the
// mechanism: there is no per-user rule anywhere in the schema, and a request
// for one Volunteer and a request for another resolve the identical map.
func TestFieldRuleIsPerRoleNotPerUser(t *testing.T) {
	pool := newFieldRulesTestPool(t)
	ctx := context.Background()
	setRuleState(t, ctx, "volunteer_tribe_clan", "required")

	body := []byte(`{"tribe_clan":""}`)

	// Volunteer #1 — the record the operator had open.
	first, err := checkFieldRules(ctx, pool, fieldRulePrefixForRole(3), true, body)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if first == nil || first.Column != "tribe_clan" {
		t.Fatalf("the rule did not bind for the edited volunteer: %+v", first)
	}
	// Volunteer #2 — a different person, never opened. Same refusal, which is
	// exactly what the confirmation dialog in the dashboard warns about.
	second, err := checkFieldRules(ctx, pool, fieldRulePrefixForRole(3), true, body)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if second == nil || second.Column != "tribe_clan" {
		t.Fatalf("the rule did not reach a second volunteer: %+v", second)
	}
	// A Grantor is untouched — the namespaces do not leak into each other.
	other, err := checkFieldRules(ctx, pool, fieldRulePrefixForRole(1), true, body)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if other != nil {
		t.Fatalf("a volunteer rule reached a grantor: %+v", other)
	}
}

// TestFieldRuleColumnStatesResolvesEveryRoleKey — the mapping is only useful
// if it can place EVERY seeded key for the three app roles. A key this file
// cannot resolve is a field staff can toggle on the Field Rules page that the
// dashboard form will then quietly ignore, which is worse than not offering
// the toggle at all.
func TestFieldRuleColumnStatesResolvesEveryRoleKey(t *testing.T) {
	pool := newFieldRulesTestPool(t)
	ctx := context.Background()

	// The columns the profile actually has. `email` lives on `users`, not on
	// `user_profiles`, and is the one governed key that is legitimately not a
	// profile column.
	rows, err := pool.Query(ctx,
		`SELECT column_name FROM information_schema.columns WHERE table_name = 'user_profiles'`)
	if err != nil {
		t.Fatalf("read columns: %v", err)
	}
	defer rows.Close()
	cols := map[string]bool{"email": true}
	for rows.Next() {
		var c string
		if err := rows.Scan(&c); err != nil {
			t.Fatalf("scan column: %v", err)
		}
		cols[c] = true
	}

	keys, err := pool.Query(ctx,
		`SELECT field_key FROM registration_field_rules
		  WHERE field_key LIKE 'grantor\_%' OR field_key LIKE 'recipient\_%'
		     OR field_key LIKE 'volunteer\_%'`)
	if err != nil {
		t.Fatalf("read keys: %v", err)
	}
	defer keys.Close()
	for keys.Next() {
		var k string
		if err := keys.Scan(&k); err != nil {
			t.Fatalf("scan key: %v", err)
		}
		for _, col := range fieldRuleColumns(k) {
			if !cols[col] {
				t.Errorf("rule %q maps to %q, which is not a user_profiles column — "+
					"staff can toggle it and the dashboard form will ignore it", k, col)
			}
		}
	}
}
