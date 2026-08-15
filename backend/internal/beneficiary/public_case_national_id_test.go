// Package beneficiary tests — public case listing.
//
// These cover one rule: the public, unauthenticated case list must never carry
// a beneficiary's national ID. This was a real production leak, not a
// hypothetical: GET /api/beneficiary_cases returned a national ID number to a
// caller with no bearer token at all.
//
// The rule is deliberately NOT expressed as a privacy preference. national_id
// has no key in the privacy catalogue, so no user switch could ever govern it,
// and an anonymous reader browsing aid cases has no reason to receive a
// government ID number under any setting.
package beneficiary

import "testing"

// strPtr returns a pointer to s, for building the *string fields on Case.
func strPtr(s string) *string { return &s }

// intPtr returns a pointer to n, for building Case.UserID.
func intPtr(n int) *int { return &n }

// TestStripNationalIDsClearsEveryCase pins the core guarantee. It asserts on
// every element rather than the first, because the bug it guards against would
// plausibly return in the shape of a loop that misses an edge.
func TestStripNationalIDsClearsEveryCase(t *testing.T) {
	items := []Case{
		{CaseCode: "CSE-0001", NationalID: strPtr("199012345678")},
		{CaseCode: "CSE-0002", NationalID: strPtr("200187654321")},
		{CaseCode: "CSE-0003", NationalID: strPtr("197755554444")},
	}

	stripNationalIDs(items)

	for i, c := range items {
		if c.NationalID != nil {
			t.Errorf("items[%d] (%s): national ID survived as %q, want nil",
				i, c.CaseCode, *c.NationalID)
		}
	}
}

// TestStripNationalIDsCoversOwnerlessCases is the regression that matters most.
//
// The per-owner privacy loop skips any case whose UserID is nil — there is no
// owner whose settings could be consulted. Those rows therefore receive NO
// masking from that mechanism, and in production they were exactly the rows
// being served. A national ID must be cleared on them regardless.
func TestStripNationalIDsCoversOwnerlessCases(t *testing.T) {
	items := []Case{
		{CaseCode: "CSE-OWNED", UserID: intPtr(42), NationalID: strPtr("199012345678")},
		{CaseCode: "CSE-ORPHAN", UserID: nil, NationalID: strPtr("200187654321")},
	}

	stripNationalIDs(items)

	if items[1].NationalID != nil {
		t.Fatalf("ownerless case leaked national ID %q — this row is skipped by the "+
			"per-owner privacy loop, so stripping must not depend on ownership",
			*items[1].NationalID)
	}
	if items[0].NationalID != nil {
		t.Fatalf("owned case leaked national ID %q", *items[0].NationalID)
	}
}

// TestStripNationalIDsLeavesOtherFieldsAlone guards the opposite failure: an
// over-broad fix that blanks the listing. The public list exists to show donors
// real cases, so the case-facing columns must survive untouched.
func TestStripNationalIDsLeavesOtherFieldsAlone(t *testing.T) {
	items := []Case{{
		CaseCode:    "CSE-0001",
		PublicTitle: "Displaced family struggling to afford food",
		FullName:    strPtr("Zaid Rasheed"),
		City:        strPtr("Duhok"),
		NationalID:  strPtr("199012345678"),
	}}

	stripNationalIDs(items)

	if items[0].PublicTitle == "" {
		t.Error("public title was cleared; the listing needs it to be useful")
	}
	if items[0].CaseCode != "CSE-0001" {
		t.Error("case code was cleared")
	}
	if items[0].City == nil || *items[0].City != "Duhok" {
		t.Error("city was cleared")
	}
	// full_name is masked by the privacy layer per the owner's own choice, not
	// here — stripNationalIDs must not pre-empt that decision in either
	// direction.
	if items[0].FullName == nil || *items[0].FullName != "Zaid Rasheed" {
		t.Error("full name was cleared here; that belongs to the privacy layer")
	}
}

// TestStripNationalIDsHandlesEmptySlice — the list is empty whenever no case is
// approved, which is the state a fresh install is in.
func TestStripNationalIDsHandlesEmptySlice(t *testing.T) {
	stripNationalIDs([]Case{})
	stripNationalIDs(nil)
}
