// group_alias_test.go pins localizedGroupAlias, the pure word lookup behind a
// masked chat-group push's per-language sender label (OPOS #26434).
//
// templates_group_alias_test.go pins the finished push titles. This file pins
// the helper's own contract, including inputs no template passes today (an
// unknown language code, an empty label), so a future caller cannot quietly
// get a translation it did not ask for. Pure: no database needed.
package notify

import "testing"

// TestLocalizedGroupAliasTranslatesServerLabels pins every generated label
// shape against every language that has a word for it.
func TestLocalizedGroupAliasTranslatesServerLabels(t *testing.T) {
	for _, tc := range []struct{ label, lang, want string }{
		{"Donor 1", "ar", "مانح 1"},
		{"Donor 1", "ckb", "بەخشەر 1"},
		{"Donor 1", "kmr", "بەخشەر 1"},
		{"Beneficiary 7", "ar", "مستحق 7"},
		{"Beneficiary 7", "ckb", "وەرگری شایستە 7"},
		{"Beneficiary 7", "kmr", "وەرگرێ شایستە 7"},
		{"Volunteer 250", "ar", "متطوع 250"},
		{"Volunteer 250", "ckb", "خۆبەخش 250"},
		{"Volunteer 250", "kmr", "خۆبەخش 250"},
		{"Member 9", "ar", "عضو 9"},
		{"Support", "ar", "فريق الدعم"},
		{"Member", "ar", "عضو"},
	} {
		t.Run(tc.label+"/"+tc.lang, func(t *testing.T) {
			if got := localizedGroupAlias(tc.label, tc.lang); got != tc.want {
				t.Errorf("localizedGroupAlias(%q, %q) = %q, want %q", tc.label, tc.lang, got, tc.want)
			}
		})
	}
}

// TestLocalizedGroupAliasPassesEverythingElseThrough pins the fallbacks:
// English (which keeps the server's words by decision), a language with no
// word for a label, an unknown language code, a custom label and an empty label
// all come back exactly as given.
func TestLocalizedGroupAliasPassesEverythingElseThrough(t *testing.T) {
	for _, tc := range []struct {
		name, label, lang string
	}{
		{"English keeps Donor", "Donor 1", "en"},
		{"English keeps Beneficiary", "Beneficiary 7", "en"},
		{"English keeps Volunteer", "Volunteer 3", "en"},
		{"English keeps numbered Member", "Member 9", "en"},
		{"English keeps Support", "Support", "en"},
		{"English keeps Member", "Member", "en"},
		{"Member has no Sorani word", "Member 9", "ckb"},
		{"Member has no Badini word", "Member 9", "kmr"},
		{"bare Member has no Sorani word", "Member", "ckb"},
		{"bare Member has no Badini word", "Member", "kmr"},
		{"Support has no Sorani word for the team", "Support", "ckb"},
		{"Support has no Badini word for the team", "Support", "kmr"},
		{"unknown language", "Donor 1", "fr"},
		{"empty language", "Donor 1", ""},
		{"language codes are lower-case", "Donor 1", "AR"},
		{"custom label", "Ahmad's family", "ar"},
		{"empty label", "", "ar"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := localizedGroupAlias(tc.label, tc.lang); got != tc.label {
				t.Errorf("localizedGroupAlias(%q, %q) = %q, want it unchanged", tc.label, tc.lang, got)
			}
		})
	}
}
