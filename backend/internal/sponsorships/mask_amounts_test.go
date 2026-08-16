// Package sponsorships tests — amount masking on the browse listing.
//
// GET /api/sponsorships with no user_id is the browse directory: it returns
// every sponsorship to any caller holding a bearer. It selected amount,
// currency and beneficiary_case_id with no masking of any kind.
//
// That defeated a protection the code already had. The `as=beneficiary` view
// blanks Amount and Currency on purpose (#53) so an eligible person cannot see
// the money being paid on their behalf — and that same person could read all of
// it, correlated to their own case id, by requesting the plain listing instead.
package sponsorships

import "testing"

// donor returns a Sponsorship funded by donorID, for table construction.
func donor(donorID int, amount string) Sponsorship {
	return Sponsorship{DonorUserID: &donorID, Amount: amount, Currency: "IQD"}
}

// TestViewerSeesOnlyTheirOwnAmounts is the core rule: my figures stay, everyone
// else's are blanked. Both halves matter — blanking everything would break the
// donor's own view, which is the reason this is not a blanket wipe.
func TestViewerSeesOnlyTheirOwnAmounts(t *testing.T) {
	items := []Sponsorship{
		donor(7, "250000"),
		donor(99, "1000000"),
		donor(7, "75000"),
	}

	MaskAmountsForViewer(items, 7)

	if items[0].Amount != "250000" || items[0].Currency != "IQD" {
		t.Errorf("viewer's own row was blanked: amount=%q currency=%q",
			items[0].Amount, items[0].Currency)
	}
	if items[2].Amount != "75000" {
		t.Errorf("viewer's second own row was blanked: %q", items[2].Amount)
	}
	if items[1].Amount != "" || items[1].Currency != "" {
		t.Errorf("another donor's money leaked: amount=%q currency=%q",
			items[1].Amount, items[1].Currency)
	}
}

// TestBeneficiaryCannotReadTheMoneyPaidForTheirCase is the regression that
// motivated the fix. A beneficiary funds nothing, so every amount is blanked —
// including on the row carrying their own beneficiary_case_id, which is the one
// the `as=beneficiary` branch already refuses to show them.
func TestBeneficiaryCannotReadTheMoneyPaidForTheirCase(t *testing.T) {
	caseID := int64(4242)
	items := []Sponsorship{
		{DonorUserID: intp(99), BeneficiaryCaseID: &caseID, Amount: "1000000", Currency: "IQD"},
	}

	// Viewer 55 is the eligible person: they appear nowhere as a donor.
	MaskAmountsForViewer(items, 55)

	if items[0].Amount != "" || items[0].Currency != "" {
		t.Fatalf("the eligible person could read the money paid for their own case "+
			"(case %d): amount=%q currency=%q — this is exactly what the "+
			"as=beneficiary view blanks on purpose",
			caseID, items[0].Amount, items[0].Currency)
	}
	// The row itself must survive: the browse directory still shows that the
	// case IS sponsored, which is not secret. Only the figure is.
	if items[0].BeneficiaryCaseID == nil {
		t.Error("the row was gutted; only amount and currency should be blanked")
	}
}

// TestAnonymousViewerSeesNoAmounts — viewerID 0 means no bearer, or a caller we
// cannot attribute. Such a viewer funds nothing, so nothing is theirs to see.
// Guarded explicitly because `viewerID > 0` is the condition that makes a NULL
// donor_user_id (an org-created sponsorship) not accidentally match.
func TestAnonymousViewerSeesNoAmounts(t *testing.T) {
	items := []Sponsorship{donor(7, "250000"), {Amount: "500000", Currency: "IQD"}}

	MaskAmountsForViewer(items, 0)

	for i := range items {
		if items[i].Amount != "" || items[i].Currency != "" {
			t.Errorf("items[%d]: anonymous viewer saw amount=%q currency=%q",
				i, items[i].Amount, items[i].Currency)
		}
	}
}

// TestOrgOwnedRowsAreMaskedForEveryone — a sponsorship with a NULL donor_user_id
// belongs to no user account, so no viewer can claim it by matching. A nil owner
// must never be treated as "mine".
func TestOrgOwnedRowsAreMaskedForEveryone(t *testing.T) {
	items := []Sponsorship{{DonorUserID: nil, Amount: "900000", Currency: "IQD"}}

	MaskAmountsForViewer(items, 7)

	if items[0].Amount != "" {
		t.Fatalf("a row with no donor was treated as the viewer's own: %q", items[0].Amount)
	}
}

// TestMaskAmountsHandlesEmpty — the listing is empty on a fresh install.
func TestMaskAmountsHandlesEmpty(t *testing.T) {
	MaskAmountsForViewer([]Sponsorship{}, 7)
	MaskAmountsForViewer(nil, 7)
}

// intp returns a pointer to n, for building DonorUserID.
func intp(n int) *int { return &n }
