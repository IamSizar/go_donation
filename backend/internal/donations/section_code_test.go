// M1 — a donation to a named project must carry a PRJ- reference, not GEN-.
//
// THE SHAPE OF THE BUG
// Migration 084 seeded four new Transaction-Code namespaces — PRD, MRG, PRJ,
// ACH — "editable from the Admin Dashboard like the existing ones". Two of them
// got call sites the same day (marketplace → PRD, marriage → MRG). `projects`
// did not. A project donation has no campaign, so donation_kind resolved to
// "general" and the reference came back GEN-000042, filed with the general
// fund. The owner asked for independent ranges per section and got them for
// three of the five sections they actually use.
//
// WHY THE FIX IS NOT "SET donation_kind = projects"
// donations.donation_kind carries a CHECK constraint listing exactly
// ('general','campaign','sponsorship','in_kind','operational')
// — migrations/001_full_v2.sql:390. Writing 'projects' there would violate it
// and every project donation would fail to save. So the code NAMESPACE is
// resolved separately from the stored kind, and this file pins that split.
//
// These are pure-function tests: codeSection() takes no database, which is the
// reason the branch was extracted rather than left inline in Insert().
package donations

import "testing"

func strptr(s string) *string { return &s }

func TestCodeSectionRoutesProjectDonationsToTheProjectsNamespace(t *testing.T) {
	slug := strptr("orphan_sponsorship")

	cases := []struct {
		name         string
		donationKind string
		projectSlug  *string
		want         string
	}{
		{
			// The defect, exactly: this is what the app sends when a donor
			// picks a project from the list.
			name:         "project picked, no campaign -> projects",
			donationKind: "general",
			projectSlug:  slug,
			want:         "projects",
		},
		{
			name:         "no project -> general, unchanged",
			donationKind: "general",
			projectSlug:  nil,
			want:         "general",
		},
		{
			// A campaign is the more specific thing being funded, and CAM- has
			// been correct since migration 026. A stray slug must not steal it.
			name:         "campaign wins over a project slug",
			donationKind: "campaign",
			projectSlug:  slug,
			want:         "campaign",
		},
		{
			// "Donation to Support the Organization" — the donor named this
			// section explicitly, so it outranks a leftover slug.
			name:         "operational wins over a project slug",
			donationKind: "operational",
			projectSlug:  slug,
			want:         "operational",
		},
		{
			name:         "sponsorship is untouched",
			donationKind: "sponsorship",
			projectSlug:  slug,
			want:         "sponsorship",
		},
		{
			name:         "in_kind is untouched",
			donationKind: "in_kind",
			projectSlug:  nil,
			want:         "in_kind",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := codeSection(tc.donationKind, tc.projectSlug); got != tc.want {
				t.Fatalf("codeSection(%q, %v) = %q, want %q",
					tc.donationKind, tc.projectSlug, got, tc.want)
			}
		})
	}
}

func TestCodeSectionTreatsBlankSlugAsNoProject(t *testing.T) {
	// The handler only sets the pointer for a non-empty value, but a pointer to
	// whitespace would otherwise route a plain general gift into PRJ and burn a
	// number out of the project sequence for nothing.
	for _, blank := range []*string{strptr(""), strptr("   "), strptr("\t")} {
		if got := codeSection("general", blank); got != "general" {
			t.Fatalf("codeSection(general, %q) = %q, want general", *blank, got)
		}
	}
}

func TestSectionLabelArHasNoEnglishForAnyIssuedSection(t *testing.T) {
	// The arrival SMS is Arabic. Before this fix `sectionLabelAr` knew only the
	// five donation_kinds and returned the raw key for anything else — so the
	// first PRJ donation would have texted the English word "projects" into an
	// otherwise Arabic message. Same English-leak shape as group B, in an SMS.
	//
	// Every section that can now reach notifySectionArrival is checked, not
	// just the new one: the gap was in the fallback, so the fallback is what
	// this pins.
	sections := []string{
		"general", "campaign", "sponsorship", "in_kind", "operational",
		"projects", "products", "marriage", "achievements",
	}
	for _, section := range sections {
		label := sectionLabelAr(section)
		if label == section {
			t.Errorf("sectionLabelAr(%q) returned the key itself — the SMS would "+
				"carry an English word", section)
		}
		for _, r := range label {
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
				t.Errorf("sectionLabelAr(%q) = %q contains a Latin letter", section, label)
				break
			}
		}
	}
}
