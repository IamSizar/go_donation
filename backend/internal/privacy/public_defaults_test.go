// public_defaults_test.go — what an anonymous reader may see.
//
// The case that prompted these: GET /api/beneficiary_cases, no credentials,
// returned a named applicant's phone and street address beside a description
// of their hardship. Nothing was broken — the applicant had simply never
// opened the Privacy Settings screen, and only saved choices were enforced.
//
// These tests pin the three rules that fixed it, and the two that must NOT
// change with it: a signed-in reader sees what they always saw, and an owner
// still sees their own data.
package privacy

import "testing"

// viewerWith builds a Viewer directly. LoadFor needs a pool; the decision being
// tested is pure, so the settings and catalogue are supplied here instead.
func viewerWith(viewerID int64, hidden map[string]bool, defaults map[string]bool) Viewer {
	return Viewer{
		set:            Set{7: Settings{hidden: hidden}},
		viewerID:       viewerID,
		publicDefaults: defaults,
	}
}

func strp(s string) *string { return &s }

// phone and address ship default_hidden=true; this is the leak that was live.
func TestAnonymousReaderDoesNotSeeDefaultHiddenFields(t *testing.T) {
	v := viewerWith(0, nil, map[string]bool{"phone": true, "address": true})

	if got := v.Field(7, FieldPhone, strp("9647502213355")); got != nil {
		t.Errorf("phone served to an anonymous reader: %q", *got)
	}
	if got := v.Field(7, FieldAddress, strp("Sumel District, Street 12, House 45")); got != nil {
		t.Errorf("address served to an anonymous reader: %q", *got)
	}
}

// gender/date_of_birth ship default_hidden=false. The fallback is the
// catalogue's intent, not a blanket redaction — a case listing still has to
// describe someone.
func TestAnonymousReaderStillSeesFieldsTheCatalogueAllows(t *testing.T) {
	v := viewerWith(0, nil, map[string]bool{"phone": true, "address": true})

	if got := v.Field(7, FieldGender, strp("Male")); got == nil {
		t.Error("gender withheld though the catalogue defaults it visible")
	}
	if got := v.Name(7, strp("Zaid Rasheed")); got == nil {
		t.Error("name withheld though the catalogue defaults it visible")
	}
}

// The narrow half of the decision: nothing an existing signed-in user sees
// changes. Applying default_hidden to them would retroactively hide every
// phone app-wide, which is a product call and not this fix.
func TestSignedInReaderIsUnaffectedByTheDefaults(t *testing.T) {
	v := viewerWith(99, nil, map[string]bool{"phone": true, "address": true})

	if got := v.Field(7, FieldPhone, strp("9647502213355")); got == nil {
		t.Error("phone withheld from a signed-in reader; the defaults must not apply to them")
	}
}

// A saved choice is still the strongest signal, for every reader.
func TestSavedChoiceStillWinsForEveryone(t *testing.T) {
	hidden := map[string]bool{"gender": true}

	if got := viewerWith(99, hidden, nil).Field(7, FieldGender, strp("Male")); got != nil {
		t.Errorf("saved hide ignored for a signed-in reader: %q", *got)
	}
	if got := viewerWith(0, hidden, nil).Field(7, FieldGender, strp("Male")); got != nil {
		t.Errorf("saved hide ignored for an anonymous reader: %q", *got)
	}
}

// A user is never masked from themselves — an anonymous viewer id is 0, and so
// is "no owner recorded", so the short-circuit must not collide with the new
// fallback.
func TestOwnerAlwaysSeesTheirOwnData(t *testing.T) {
	v := viewerWith(7, map[string]bool{"phone": true}, map[string]bool{"phone": true})
	if got := v.Field(7, FieldPhone, strp("9647502213355")); got == nil {
		t.Error("owner was masked from their own phone")
	}
}

// An ownerless row (user_id NULL) has nobody whose preferences could apply.
// It must not accidentally start returning data through the ownerID==0 branch.
func TestOwnerlessRowIsUnchangedByTheFallback(t *testing.T) {
	v := viewerWith(0, nil, map[string]bool{"phone": true})
	// ownerID 0 short-circuits before the fallback, by design — those rows are
	// stripped by their own path (stripOwnerlessPersonalDetails), not this one.
	if got := v.Field(0, FieldPhone, strp("07701234567")); got == nil {
		t.Error("ownerless handling changed; that path is owned by the beneficiary store")
	}
}
