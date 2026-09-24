// templates_sponsorship_localized_name_test.go — an Arabic or Kurdish
// sponsorship-accepted push must name the project in THAT language.
//
// Client feedback round 1: the four bodies already interpolated the project
// name correctly (templates.go), but the caller only ever had the English
// column to hand it, so every language got the English title inside otherwise
// Arabic/Kurdish copy. Taking a LocalText — the same shape
// chatThreadNewMessageMsg already takes for its sender name — is what makes a
// per-language name expressible at all.
package notify

import (
	"strings"
	"testing"
)

// projectFourLanguages is one project titled differently in each language, so
// a body carrying the wrong language's title is unambiguous.
var projectFourLanguages = LocalText{
	En:  "Winter Relief",
	Ar:  "إغاثة الشتاء",
	Ckb: "یارمەتیی زستان",
	Kmr: "هاریکاریا زڤستانێ",
}

func TestSponsorshipAcceptedMsg_EachLanguageNamesTheProjectInThatLanguage(t *testing.T) {
	m := SponsorshipAcceptedMsg("50000", "IQD", projectFourLanguages, 7)

	cases := []struct {
		lang, body, want string
	}{
		{"En", m.Body.En, projectFourLanguages.En},
		{"Ar", m.Body.Ar, projectFourLanguages.Ar},
		{"Ckb", m.Body.Ckb, projectFourLanguages.Ckb},
		{"Kmr", m.Body.Kmr, projectFourLanguages.Kmr},
	}
	for _, tc := range cases {
		if !strings.Contains(tc.body, tc.want) {
			t.Errorf("%s body does not name the project in %s: got %q, want it to contain %q",
				tc.lang, tc.lang, tc.body, tc.want)
		}
	}

	// The specific reported symptom: English text inside the Arabic sentence.
	for _, tc := range cases[1:] {
		if strings.Contains(tc.body, projectFourLanguages.En) {
			t.Errorf("%s body carries the ENGLISH project title: %q", tc.lang, tc.body)
		}
	}
}

// TestSponsorshipAcceptedMsg_FallsBackToEnglishWhenALanguageIsMissing covers
// the common real row: project_title is NOT NULL but project_title_ar /
// _sorani / _badini are nullable and usually empty. The caller COALESCEs, so
// the template simply receives the English title in every slot — the body must
// still be a complete sentence, not the empty-name variant.
func TestSponsorshipAcceptedMsg_FallsBackToEnglishWhenALanguageIsMissing(t *testing.T) {
	onlyEnglish := LocalText{En: "Winter Relief", Ar: "Winter Relief", Ckb: "Winter Relief", Kmr: "Winter Relief"}
	m := SponsorshipAcceptedMsg("50000", "IQD", onlyEnglish, 7)
	for name, body := range map[string]string{"En": m.Body.En, "Ar": m.Body.Ar, "Ckb": m.Body.Ckb, "Kmr": m.Body.Kmr} {
		if !strings.Contains(body, "Winter Relief") {
			t.Errorf("%s body does not name the project: %q", name, body)
		}
	}
}

// TestSponsorshipAcceptedMsg_EmptyLocalTextKeepsTheGeneralSupportSentence
// pins that widening the parameter did not break the "General support"
// (no case, no project request) path, which has its own complete sentence per
// language rather than a blank interpolation.
func TestSponsorshipAcceptedMsg_EmptyLocalTextKeepsTheGeneralSupportSentence(t *testing.T) {
	m := SponsorshipAcceptedMsg("50000", "IQD", LocalText{}, 7)
	for name, body := range map[string]string{"En": m.Body.En, "Ar": m.Body.Ar, "Ckb": m.Body.Ckb, "Kmr": m.Body.Kmr} {
		if strings.Contains(body, `""`) || strings.Contains(body, "«»") {
			t.Errorf("%s body interpolates a blank quoted name: %q", name, body)
		}
	}
	if !strings.Contains(m.Body.Ar, "كفالتك") {
		t.Errorf("Ar body does not read as a sponsorship sentence: %q", m.Body.Ar)
	}
}
