package notify

import (
	"strings"
	"testing"
)

// OPOS #25279 — a sponsorship with neither a beneficiary_case_id nor a
// project_request_id ("General support", a legitimate, intentional shape —
// see sponsorships.Store.Insert) resolves to an empty projectName. These
// pin that an empty name gets its own complete sentence per language,
// instead of interpolating a blank (`للمشروع ""`) or the raw English
// literal "General support" into an otherwise-Arabic/Kurdish sentence.

func TestSponsorshipAcceptedMsg_NamesTheProjectWhenKnown(t *testing.T) {
	m := SponsorshipAcceptedMsg("50000", "IQD", "Winter Relief", 7)
	for name, body := range map[string]string{"En": m.Body.En, "Ar": m.Body.Ar, "Ckb": m.Body.Ckb, "Kmr": m.Body.Kmr} {
		if !strings.Contains(body, "Winter Relief") {
			t.Errorf("%s body does not name the project: %q", name, body)
		}
	}
}

func TestSponsorshipAcceptedMsg_GeneralSupportHasNoBlankOrRawEnglish(t *testing.T) {
	m := SponsorshipAcceptedMsg("50000", "IQD", "", 7)
	for name, body := range map[string]string{"En": m.Body.En, "Ar": m.Body.Ar, "Ckb": m.Body.Ckb, "Kmr": m.Body.Kmr} {
		if strings.Contains(body, `""`) {
			t.Errorf("%s body still interpolates a blank quoted name: %q", name, body)
		}
		if strings.Contains(body, "General support") {
			t.Errorf("%s body leaks the raw English literal instead of localized copy: %q", name, body)
		}
	}
	// The non-English bodies must still say something coherent — not just
	// avoid the two failure modes above.
	if !strings.Contains(m.Body.Ar, "كفالتك") {
		t.Errorf("Ar body does not read as a sponsorship sentence: %q", m.Body.Ar)
	}
}

func TestSponsorshipCancelledByDonorMsg_GeneralSupportHasNoBlankOrRawEnglish(t *testing.T) {
	m := SponsorshipCancelledByDonorMsg("", 8)
	for name, body := range map[string]string{"En": m.Body.En, "Ar": m.Body.Ar, "Ckb": m.Body.Ckb, "Kmr": m.Body.Kmr} {
		if strings.Contains(body, `""`) || strings.Contains(body, "«»") {
			t.Errorf("%s body still interpolates a blank name: %q", name, body)
		}
	}
}

func TestSponsorshipStatusChangedMsg_LocalizesTheStatusWord(t *testing.T) {
	for _, status := range []string{"paused", "delayed", "completed"} {
		m := SponsorshipStatusChangedMsg("Winter Relief", status, 9)
		if strings.Contains(m.Body.Ar, status) {
			t.Errorf("status=%q: Ar body leaks the raw English status word: %q", status, m.Body.Ar)
		}
		if strings.Contains(m.Body.Ckb, status) {
			t.Errorf("status=%q: Ckb body leaks the raw English status word: %q", status, m.Body.Ckb)
		}
		if strings.Contains(m.Body.Kmr, status) {
			t.Errorf("status=%q: Kmr body leaks the raw English status word: %q", status, m.Body.Kmr)
		}
		if !strings.Contains(m.Body.En, status) {
			t.Errorf("status=%q: En body should still read the plain status word: %q", status, m.Body.En)
		}
	}
}

func TestSponsorshipStatusChangedMsg_GeneralSupportHasNoBlankName(t *testing.T) {
	m := SponsorshipStatusChangedMsg("", "paused", 9)
	for name, body := range map[string]string{"En": m.Body.En, "Ar": m.Body.Ar, "Ckb": m.Body.Ckb, "Kmr": m.Body.Kmr} {
		if strings.Contains(body, `""`) || strings.Contains(body, "«»") {
			t.Errorf("%s body still interpolates a blank name: %q", name, body)
		}
	}
}
