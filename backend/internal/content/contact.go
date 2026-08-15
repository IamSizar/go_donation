// Contact details of an editable content page (K13).
//
// WHY THIS FILE EXISTS
// "تواصل معنا" was a single sentence. The client asked it for a logo, a phone
// number, WhatsApp, an email address, social links and an address, and none of
// them existed as fields — `app_content` held one title and one body per locale
// and nothing else, so nothing on the screen could be tapped, dialled or
// opened.
//
// Migration 112 adds the columns; content.go stores and reads them. This file
// is the VALIDATION, which is the half that decides whether the feature is
// trustworthy: a phone number that is prose, or a social link the app cannot
// open, is a control that looks real and does nothing.
//
// The dashboard runs the same rules inline for immediate feedback. This copy is
// the source of truth, because a client is never the control.
package content

import (
	"fmt"
	"strings"
	"unicode"
)

// Field length caps. These bound the payload at the trust boundary; they are
// generous enough that no honest value hits them, and small enough that a
// paste-gone-wrong is refused instead of stored.
const (
	maxPhoneLen   = 64
	maxEmailLen   = 255
	maxPathLen    = 500
	maxSocialLen  = 2000
	maxAddressLen = 500
)

// minPhoneDigits is what separates a phone number from prose.
//
// Counting DIGITS rather than banning letters is deliberate: "(0750) 858-2031
// ext. 12" is a real public line and must be accepted, while "call us any time"
// must not. Five is below any dialable number, including short codes, so the
// rule rejects text without ever rejecting a number.
const minPhoneDigits = 5

// ValidateContact checks the K13 contact fields of a page.
//
// It returns the FIRST field that fails and a stable machine code for why —
// empty strings when everything is acceptable. The code is what the dashboard
// translates (`error.*`), so the operator reads the reason in their own
// language rather than English prose from a Go file.
//
// Every field is optional. Empty is the state every page is in today and the
// state the owner fills in over time, so "" is always valid; the rules only
// apply to a value that is actually present.
func ValidateContact(c Content) (field, code string) {
	if len(c.LogoPath) > maxPathLen || strings.ContainsAny(c.LogoPath, "\n\r") {
		return "logo_path", "invalid_logo_path"
	}
	if f, k := validatePhone("contact_phone", c.ContactPhone); f != "" {
		return f, k
	}
	if f, k := validatePhone("contact_whatsapp", c.ContactWhatsApp); f != "" {
		return f, k
	}
	if !validEmail(c.ContactEmail) {
		return "contact_email", "invalid_email"
	}
	if !validSocialLinks(c.SocialLinks) {
		return "social_links", "invalid_social_links"
	}
	for _, a := range []struct {
		field, value string
	}{
		{"address_en", c.AddressEn},
		{"address_ar", c.AddressAr},
		{"address_ckb", c.AddressCkb},
		{"address_kmr", c.AddressKmr},
	} {
		if len(a.value) > maxAddressLen {
			return a.field, "value_too_long"
		}
	}
	return "", ""
}

// ContactRejectionMessage is the English fallback prose for a validation code.
//
// The dashboard renders the translated `error.<code>` instead; this exists for
// the log and for any non-SPA caller, which would otherwise get a bare code.
func ContactRejectionMessage(field, code string) string {
	switch code {
	case "invalid_phone":
		return fmt.Sprintf("%s must be a phone number (at least %d digits).", field, minPhoneDigits)
	case "invalid_email":
		return "Enter a valid email address, or leave it empty."
	case "invalid_social_links":
		return "Put one social media link per line, each with a domain (for example facebook.com/yourpage)."
	case "invalid_logo_path":
		return "That logo path is not valid."
	case "value_too_long":
		return fmt.Sprintf("%s is too long.", field)
	default:
		return "That value is not valid."
	}
}

// validatePhone applies the shared rule to one of the two number fields. It is
// a single line of text, so a newline is a paste accident rather than a number.
func validatePhone(field, value string) (string, string) {
	if strings.TrimSpace(value) == "" {
		return "", ""
	}
	if len(value) > maxPhoneLen || strings.ContainsAny(value, "\n\r") {
		return field, "invalid_phone"
	}
	digits := 0
	for _, r := range value {
		if unicode.IsDigit(r) {
			digits++
		}
	}
	if digits < minPhoneDigits {
		return field, "invalid_phone"
	}
	return "", ""
}

// validEmail applies a deliberately SHALLOW check: one "@", something either
// side of it, and a dot in the domain.
//
// Full RFC validation is a well-known trap that rejects legitimate addresses;
// the only thing worth catching here is the mistake an operator actually makes,
// which is typing an address that is not one ("info at balancenex") or omitting
// the domain suffix.
func validEmail(value string) bool {
	if strings.TrimSpace(value) == "" {
		return true
	}
	if len(value) > maxEmailLen || strings.ContainsFunc(value, unicode.IsSpace) {
		return false
	}
	local, domain, found := strings.Cut(value, "@")
	if !found || local == "" || domain == "" {
		return false
	}
	if strings.Contains(domain, "@") {
		return false
	}
	host, tld, hasDot := strings.Cut(domain, ".")
	return hasDot && host != "" && strings.TrimSuffix(tld, ".") != ""
}

// validSocialLinks checks the free-text column that partners (035) and
// city_directory_entries (100) already use — one URL per line, commas
// tolerated.
//
// Each entry must look like a host, because the app prefixes a bare host with
// "https://" and opens it (shared/utils/social_links.dart). A handle like
// "@balancenex" would become a chip that opens a broken page — worse than being
// told here to paste the full address. Blank fragments left by a trailing comma
// are dropped, exactly as the app's parser drops them.
func validSocialLinks(value string) bool {
	if strings.TrimSpace(value) == "" {
		return true
	}
	if len(value) > maxSocialLen {
		return false
	}
	for _, raw := range strings.FieldsFunc(value, func(r rune) bool { return r == '\n' || r == '\r' || r == ',' }) {
		link := strings.TrimSpace(raw)
		if link == "" {
			continue
		}
		if strings.ContainsFunc(link, unicode.IsSpace) {
			return false
		}
		// Strip a scheme before looking for the host's dot, so "https://x.com"
		// and "x.com" are judged identically.
		bare := link
		if _, after, found := strings.Cut(bare, "://"); found {
			bare = after
		}
		host, _, _ := strings.Cut(bare, "/")
		if !strings.Contains(host, ".") || strings.HasPrefix(host, ".") || strings.HasSuffix(host, ".") {
			return false
		}
	}
	return true
}
