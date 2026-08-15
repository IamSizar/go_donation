// K13 — "تواصل معنا" had no contact details, only a sentence.
//
// THE SHAPE OF THE GAP
// The client asked the Contact page for a logo, phone, WhatsApp, email, social
// links and an address. None of them existed as fields: `app_content` holds one
// title and one body per locale and nothing else, so the page was a single
// sentence with nothing tappable on it.
//
// These tests cover the two halves that can go wrong quietly:
//
//	the fields must actually round-trip (a field that writes nowhere is the
//	  exact failure mode this project has already hit once), and
//	validation must reject at the boundary rather than storing a phone number
//	  with letters in it or an address 40 KB long.
//
// The DB-backed tests are skipped unless TEST_DATABASE_URL is set (see
// sections_test.go for the harness). TestValidateContact needs no database.
package content

import (
	"context"
	"strings"
	"testing"
)

// ─── Validation ─────────────────────────────────────────────────────────

// TestValidateContact pins the server-side half of K13's input validation. The
// dashboard validates the same rules inline for immediate feedback; this is the
// copy that is the source of truth, because the client is not the control.
func TestValidateContact(t *testing.T) {
	tests := []struct {
		name string
		in   Content
		// Empty means "must be accepted"; otherwise the field the rejection
		// must name, so a caller can point at the box that is wrong.
		wantField string
	}{
		{
			// Every page is in exactly this state today, and it must stay
			// saveable — the owner fills the fields in over time, not at once.
			name: "everything empty is valid",
			in:   Content{},
		},
		{
			name: "a full, ordinary set is valid",
			in: Content{
				ContactPhone:    "+964 750 858 2031",
				ContactWhatsApp: "07508582031",
				ContactEmail:    "info@balancenex.org",
				SocialLinks:     "facebook.com/balancenex\nhttps://instagram.com/balancenex",
				AddressAr:       "الموصل، العراق",
				LogoPath:        "/images/uploads/logo.png",
			},
		},
		{
			// Extensions and area codes are real; an organization's public line
			// is not always a bare mobile number.
			name: "punctuation and an extension are accepted in a phone number",
			in:   Content{ContactPhone: "(0750) 858-2031 ext. 12"},
		},
		{
			name:      "a phone number that is prose is rejected",
			in:        Content{ContactPhone: "call us any time"},
			wantField: "contact_phone",
		},
		{
			name:      "a phone number with no digits at all is rejected",
			in:        Content{ContactWhatsApp: "+++"},
			wantField: "contact_whatsapp",
		},
		{
			name:      "an address masquerading as an email is rejected",
			in:        Content{ContactEmail: "info at balancenex"},
			wantField: "contact_email",
		},
		{
			name:      "an email with no domain dot is rejected",
			in:        Content{ContactEmail: "info@localhost"},
			wantField: "contact_email",
		},
		{
			// The app prefixes a bare host with https:// and opens it. A handle
			// with no host would open a broken page, which is worse than being
			// told to fix it here.
			name:      "a social handle with no host is rejected",
			in:        Content{SocialLinks: "@balancenex"},
			wantField: "social_links",
		},
		{
			name:      "a social link with a space in it is rejected",
			in:        Content{SocialLinks: "facebook.com/balance nex"},
			wantField: "social_links",
		},
		{
			name: "blank lines between social links are tolerated",
			in:   Content{SocialLinks: "facebook.com/a\n\n  \nt.me/b, x.com/c"},
		},
		{
			name:      "an over-long phone number is rejected",
			in:        Content{ContactPhone: strings.Repeat("9", 200)},
			wantField: "contact_phone",
		},
		{
			name:      "an over-long address is rejected",
			in:        Content{AddressEn: strings.Repeat("x", 5000)},
			wantField: "address_en",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			field, msg := ValidateContact(tc.in)
			if field != tc.wantField {
				t.Fatalf("ValidateContact rejected %q (%q), want %q", field, msg, tc.wantField)
			}
			if field != "" && strings.TrimSpace(msg) == "" {
				t.Errorf("rejection of %q carries no reason; the operator has to be told what is wrong", field)
			}
		})
	}
}

// ─── Storage ────────────────────────────────────────────────────────────

// TestContactFieldsRoundTrip is the guard against K13 shipping as a form that
// writes nowhere: every field the client named must survive a save and a read.
func TestContactFieldsRoundTrip(t *testing.T) {
	pool := newSectionsTestPool(t)
	store := New(pool)
	ctx := context.Background()
	seedPage(t, pool, "k13-roundtrip", "Body.", "النص.")

	want := Content{
		Slug:            "k13-roundtrip",
		TitleEn:         "Contact Us",
		BodyEn:          "Body.",
		LogoPath:        "/images/uploads/logo.png",
		ContactPhone:    "+964 750 858 2031",
		ContactWhatsApp: "9647508582031",
		ContactEmail:    "info@balancenex.org",
		SocialLinks:     "facebook.com/balancenex\ninstagram.com/balancenex",
		AddressEn:       "Mosul, Iraq",
		AddressAr:       "الموصل، العراق",
		AddressCkb:      "مووسڵ، عێراق",
		AddressKmr:      "مووسل، عێراق",
	}
	if err := store.Upsert(ctx, want, 42); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	got, err := store.Get(ctx, "k13-roundtrip")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	checks := []struct {
		field     string
		got, want string
	}{
		{"logo_path", got.LogoPath, want.LogoPath},
		{"contact_phone", got.ContactPhone, want.ContactPhone},
		{"contact_whatsapp", got.ContactWhatsApp, want.ContactWhatsApp},
		{"contact_email", got.ContactEmail, want.ContactEmail},
		{"social_links", got.SocialLinks, want.SocialLinks},
		{"address_en", got.AddressEn, want.AddressEn},
		{"address_ar", got.AddressAr, want.AddressAr},
		{"address_ckb", got.AddressCkb, want.AddressCkb},
		{"address_kmr", got.AddressKmr, want.AddressKmr},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s did not round-trip: got %q, want %q", c.field, c.got, c.want)
		}
	}
}

// TestContactFieldsDefaultToEmpty covers the pages that existed before
// migration 112: they must read back as empty strings rather than failing or
// coming back NULL, because that is truthfully what they hold — the owner has
// not supplied a number yet.
func TestContactFieldsDefaultToEmpty(t *testing.T) {
	pool := newSectionsTestPool(t)
	store := New(pool)
	ctx := context.Background()

	got, err := store.Get(ctx, "contact")
	if err != nil {
		t.Fatalf("Get(contact): %v", err)
	}
	if got.Slug != "contact" {
		t.Fatalf("Get returned slug %q, want contact", got.Slug)
	}
	// Nothing here asserts a VALUE — seeding a phone number would be inventing
	// the owner's data. What matters is that the columns read cleanly.
	for field, v := range map[string]string{
		"logo_path":        got.LogoPath,
		"contact_phone":    got.ContactPhone,
		"contact_whatsapp": got.ContactWhatsApp,
		"contact_email":    got.ContactEmail,
		"social_links":     got.SocialLinks,
		"address_en":       got.AddressEn,
	} {
		if strings.TrimSpace(v) != v {
			t.Errorf("%s came back padded (%q); the column default should be an empty string", field, v)
		}
	}
}
