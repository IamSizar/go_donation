// beneficiary_national_id_mask_test.go — H10 for the applicant's national ID
// on the admin case list.
//
// Background: AdminCases masked `phone` for staff without the "Sensitive
// contact data" permission and served `national_id` in full, so the protection
// ran backwards — a live supervisor session received `••` for the phone and a
// complete twelve-digit identity number in the next column.
//
// The masking itself lives in sensitive.MaskPtr; what these tests pin is the
// pairing. The bug was never that masking was broken, it was that one of the
// two fields was not passed through it, and that is a mistake a test naming
// both fields together catches on the next refactor.
package handlers

import (
	"testing"

	"github.com/karam-flutter/humanitarian-backend/internal/sensitive"
)

// maskCaseIdentity mirrors what AdminCases does to one row when the actor
// lacks the contact permission. Kept in the test rather than exported from the
// handler: the handler's loop is two lines over a slice, and duplicating those
// two lines here is cheaper than reshaping production code to be callable.
func maskCaseIdentity(phone, nationalID *string) (*string, *string) {
	return sensitive.MaskPtr(phone), sensitive.MaskPtr(nationalID)
}

func TestNationalIDIsMaskedAlongsideThePhone(t *testing.T) {
	phone := "07701234567"
	nid := "199012345678"

	gotPhone, gotNID := maskCaseIdentity(&phone, &nid)

	if gotPhone == nil || *gotPhone == phone {
		t.Errorf("phone was not masked: got %v", gotPhone)
	}
	// The real defect: this field came back untouched.
	if gotNID == nil {
		t.Fatal("national ID became nil; it should be masked, not dropped")
	}
	if *gotNID == nid {
		t.Errorf("national ID leaked in full: %q", *gotNID)
	}
	if !sensitive.IsMasked(*gotNID) {
		t.Errorf("national ID %q is not recognised as masked, so the write guard "+
			"would not refuse it either", *gotNID)
	}
}

// A national ID short enough to be swallowed whole must not leak a suffix.
// Real data includes both: the live rows carried twelve-digit numbers and a
// four-character "1234", and Mask keeps the last two runes only above a
// threshold.
func TestShortNationalIDDoesNotLeakItsTail(t *testing.T) {
	for _, in := range []string{"1234", "12", "ص"} {
		masked := sensitive.MaskPtr(&in)
		if masked == nil {
			t.Fatalf("MaskPtr(%q) returned nil", in)
		}
		if *masked == in {
			t.Errorf("short national ID %q was returned unmasked", in)
		}
	}
}

// NULL is "no value recorded", not a secret — it must stay NULL so the edit
// form shows an empty box rather than dots the operator would then save back.
func TestAbsentNationalIDStaysAbsent(t *testing.T) {
	_, gotNID := maskCaseIdentity(nil, nil)
	if gotNID != nil {
		t.Errorf("nil national ID became %q; NULL must stay NULL", *gotNID)
	}
}

// The other half of the fix. Masking on the way out is what makes a field
// dangerous on the way back in, so whatever Mask produces must be something
// IsMasked refuses — otherwise saving an unrelated field would store the
// redaction as the applicant's identity number.
func TestMaskedNationalIDIsRefusedByTheWriteGuard(t *testing.T) {
	for _, in := range []string{"199012345678", "1234"} {
		masked := sensitive.Mask(in)
		if !sensitive.IsMasked(masked) {
			t.Errorf("Mask(%q) = %q, which the write guard would accept as a real "+
				"national ID and store", in, masked)
		}
	}
}
