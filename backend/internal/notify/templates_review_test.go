package notify

import (
	"strings"
	"testing"
)

// Decision notifications that carry the reviewer's reason.
//
// BeneficiaryCaseRejectedMsg used to take no reason, and its copy said
// "Please contact support for details" — because there were none to give. The
// reviewer's words went into review_notes and stopped there, so the applicant
// was sent to chase an answer that had already been written down.

const rejectionReason = "The tenancy contract is missing"

// The reason must appear in every language, and the "go ask support" line must
// step aside once there is something concrete to say.
func TestBeneficiaryCaseRejectedMsg_CarriesTheReason(t *testing.T) {
	m := BeneficiaryCaseRejectedMsg("Winter heating oil", 12, rejectionReason)

	for name, body := range map[string]string{
		"En":  m.Body.En,
		"Ar":  m.Body.Ar,
		"Ckb": m.Body.Ckb,
		"Kmr": m.Body.Kmr,
	} {
		if !strings.Contains(body, rejectionReason) {
			t.Errorf("%s body does not carry the reason: %q", name, body)
		}
		if strings.Contains(body, "contact support") {
			t.Errorf("%s body still sends the user to support for a reason it "+
				"has just given them: %q", name, body)
		}
	}
	// It still has to say WHICH case, or the alert is unplaceable.
	if !strings.Contains(m.Body.En, "Winter heating oil") {
		t.Errorf("English body does not name the case: %q", m.Body.En)
	}
	if m.RelatedEntityID != 12 || m.RelatedEntityType != "beneficiary_cases" {
		t.Errorf("related entity = %s/%d, want beneficiary_cases/12",
			m.RelatedEntityType, m.RelatedEntityID)
	}
}

// With no reason on file the old wording is still the only honest next step.
func TestBeneficiaryCaseRejectedMsg_WithoutAReasonStillPointsSomewhere(t *testing.T) {
	m := BeneficiaryCaseRejectedMsg("Winter heating oil", 12, "   ")

	if !strings.Contains(m.Body.En, "contact support") {
		t.Errorf("with no reason recorded the user must still be told where to "+
			"go, got %q", m.Body.En)
	}
	if strings.Contains(m.Body.En, "Reason:") {
		t.Errorf("an empty reason must not produce a dangling label: %q", m.Body.En)
	}
}

// reasonTail is shared with RegistrationRejectedMsg so the two "we said no,
// here is why" templates use the SAME four strings. Extracting it was the point
// — it means a second template cannot introduce a fresh guess at Kurdish, which
// is the easy mistake here because both Kurdish locales use Arabic script.
func TestReasonTail_IsSharedAndSkippedWhenEmpty(t *testing.T) {
	en, ar, ckb, kmr := reasonTail("")
	if en != "" || ar != "" || ckb != "" || kmr != "" {
		t.Errorf("an empty reason must produce no tail at all, got %q/%q/%q/%q",
			en, ar, ckb, kmr)
	}

	en, ar, ckb, kmr = reasonTail("  spaced  ")
	for name, tail := range map[string]string{"En": en, "Ar": ar, "Ckb": ckb, "Kmr": kmr} {
		if !strings.Contains(tail, "spaced") {
			t.Errorf("%s tail lost the reason: %q", name, tail)
		}
		// Trimmed at the edges, so a copy-pasted reason does not arrive with a
		// ragged gap in the middle of the sentence.
		if strings.Contains(tail, "  spaced") {
			t.Errorf("%s tail kept the caller's padding: %q", name, tail)
		}
	}

	// The four registration strings and the four case strings are now one set,
	// by construction: the same call produces both.
	regEn, regAr, regCkb, regKmr := reasonTail(rejectionReason)
	caseMsg := BeneficiaryCaseRejectedMsg("x", 1, rejectionReason)
	regMsg := RegistrationRejectedMsg(1, rejectionReason)
	for _, pair := range [][2]string{
		{regEn, caseMsg.Body.En}, {regAr, caseMsg.Body.Ar},
		{regCkb, caseMsg.Body.Ckb}, {regKmr, caseMsg.Body.Kmr},
		{regEn, regMsg.Body.En}, {regAr, regMsg.Body.Ar},
		{regCkb, regMsg.Body.Ckb}, {regKmr, regMsg.Body.Kmr},
	} {
		if !strings.HasSuffix(pair[1], pair[0]) {
			t.Errorf("body %q does not end with the shared tail %q", pair[1], pair[0])
		}
	}
}
