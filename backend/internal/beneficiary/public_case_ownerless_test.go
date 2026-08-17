// Package beneficiary tests — the ownerless public case.
//
// The public case list (GET /api/beneficiary_cases with no user_id) takes an
// OPTIONAL bearer, so an anonymous caller receives it. For a case that HAS an
// owner, the owner's personal columns pass through that owner's own Privacy
// Settings before they are serialised — the owner decided.
//
// A case with user_id = NULL has no owner, so the per-owner loop skips it and
// no preference of any kind is applied. Those rows were published in full:
// name, phone and address of a real person, to an unauthenticated reader,
// under a consent decision that nobody was ever in a position to make.
//
// The rule these tests pin: no owner means no consent, so the personal columns
// default to withheld. The case-facing columns must survive — the list exists
// so donors can see real cases, and blanking it would break the feature in
// order to fix the leak.
package beneficiary

import "testing"

// personalFields is the exact set of columns the per-owner privacy loop
// governs in ListPublicCasesForViewer (Name + the four Field calls). The
// ownerless default has to cover the SAME set: these are precisely the columns
// whose exposure is a consent decision, and an ownerless row is the one row
// where that decision was never made. Covering only some of them would leave
// an inconsistency with no principle behind it.
//
// national_id is deliberately not in this set — it is stripped from every row
// unconditionally by stripNationalIDs, owner or not, and has no privacy switch.

// TestOwnerlessCasesLoseTheirPersonalColumns is the core regression. It builds
// the row shape production was actually serving: an approved, publicly visible
// case with no user_id and a full set of contact details.
func TestOwnerlessCasesLoseTheirPersonalColumns(t *testing.T) {
	items := []Case{{
		CaseCode:    "CSE-ORPHAN",
		UserID:      nil,
		FullName:    strPtr("Zaid Rasheed"),
		Phone:       strPtr("9647701234567"),
		Address:     strPtr("Domiz Camp, Block 4, House 12"),
		Gender:      strPtr("Male"),
		DateOfBirth: strPtr("1990-04-11"),
	}}

	stripOwnerlessPersonalDetails(items)

	got := items[0]
	if got.FullName != nil {
		t.Errorf("full_name survived as %q on an ownerless case — nobody consented to publishing it", *got.FullName)
	}
	if got.Phone != nil {
		t.Errorf("phone survived as %q on an ownerless case — nobody consented to publishing it", *got.Phone)
	}
	if got.Address != nil {
		t.Errorf("address survived as %q on an ownerless case — nobody consented to publishing it", *got.Address)
	}
	if got.Gender != nil {
		t.Errorf("gender survived as %q on an ownerless case", *got.Gender)
	}
	if got.DateOfBirth != nil {
		t.Errorf("date_of_birth survived as %q on an ownerless case", *got.DateOfBirth)
	}
}

// TestOwnedCasesAreLeftToThePrivacyLayer guards the opposite failure: a fix
// that masks everything and quietly overrides the owners who DID consent.
//
// An owner who left their name visible must keep it visible. The decision for
// an owned row belongs to ListPublicCasesForViewer's per-owner loop, and this
// function must not pre-empt it in either direction.
func TestOwnedCasesAreLeftToThePrivacyLayer(t *testing.T) {
	items := []Case{{
		CaseCode: "CSE-OWNED",
		UserID:   intPtr(42),
		FullName: strPtr("Consenting Owner"),
		Phone:    strPtr("9647709999999"),
		Address:  strPtr("Erbil, 100m Street"),
	}}

	stripOwnerlessPersonalDetails(items)

	got := items[0]
	if got.FullName == nil {
		t.Error("full_name was cleared on an OWNED case; that decision belongs to the owner's Privacy Settings")
	}
	if got.Phone == nil {
		t.Error("phone was cleared on an OWNED case; that decision belongs to the owner's Privacy Settings")
	}
	if got.Address == nil {
		t.Error("address was cleared on an OWNED case; that decision belongs to the owner's Privacy Settings")
	}
}

// TestOwnerlessCasesKeepTheCaseFacingColumns is the other half of the
// guarantee. The public list exists to show donors real, identifiable CASES —
// a title, a code, a city, a category and what is actually needed. Stripping
// those to close a contact-details leak would fix the leak by deleting the
// feature.
func TestOwnerlessCasesKeepTheCaseFacingColumns(t *testing.T) {
	items := []Case{{
		CaseCode:      "CSE-ORPHAN",
		UserID:        nil,
		PublicTitle:   "Displaced family struggling to afford food",
		PublicTitleAr: strPtr("عائلة نازحة تعاني لتأمين الطعام"),
		City:          strPtr("Duhok"),
		District:      strPtr("Domiz"),
		CategorySlug:  strPtr("food"),
		ActualNeeds:   strPtr("Monthly food basket for six people"),
		FullName:      strPtr("Zaid Rasheed"),
	}}

	stripOwnerlessPersonalDetails(items)

	got := items[0]
	if got.PublicTitle != "Displaced family struggling to afford food" {
		t.Errorf("public_title = %q, want it untouched — the listing is unusable without it", got.PublicTitle)
	}
	if got.PublicTitleAr == nil {
		t.Error("public_title_ar was cleared; the Arabic listing needs it")
	}
	if got.CaseCode != "CSE-ORPHAN" {
		t.Errorf("case_code = %q, want it untouched", got.CaseCode)
	}
	if got.City == nil || *got.City != "Duhok" {
		t.Errorf("city = %v, want Duhok — a donor picks a case by where it is", got.City)
	}
	if got.District == nil || *got.District != "Domiz" {
		t.Errorf("district = %v, want Domiz", got.District)
	}
	if got.CategorySlug == nil || *got.CategorySlug != "food" {
		t.Errorf("category_slug = %v, want food — the list filters on it", got.CategorySlug)
	}
	if got.ActualNeeds == nil || *got.ActualNeeds != "Monthly food basket for six people" {
		t.Errorf("actual_needs = %v, want it untouched — it is the whole point of the card", got.ActualNeeds)
	}
}

// TestStripOwnerlessHandlesMixedAndEmptySlices — the list is a mix of owned
// and ownerless rows in production, and empty on a fresh install.
func TestStripOwnerlessHandlesMixedAndEmptySlices(t *testing.T) {
	items := []Case{
		{CaseCode: "A", UserID: intPtr(7), Phone: strPtr("9647700000001")},
		{CaseCode: "B", UserID: nil, Phone: strPtr("9647700000002")},
		{CaseCode: "C", UserID: intPtr(9), Phone: strPtr("9647700000003")},
		{CaseCode: "D", UserID: nil, Phone: strPtr("9647700000004")},
	}

	stripOwnerlessPersonalDetails(items)

	for i, c := range items {
		wantCleared := c.UserID == nil
		if wantCleared && c.Phone != nil {
			t.Errorf("items[%d] (%s): ownerless row kept phone %q", i, c.CaseCode, *c.Phone)
		}
		if !wantCleared && c.Phone == nil {
			t.Errorf("items[%d] (%s): owned row lost its phone to the ownerless default", i, c.CaseCode)
		}
	}

	stripOwnerlessPersonalDetails([]Case{})
	stripOwnerlessPersonalDetails(nil)
}
