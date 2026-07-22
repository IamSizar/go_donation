package auth

import (
	"regexp"
	"strings"
)

var (
	// Strip human formatting: spaces, dashes, parens, dots — plus any Unicode
	// whitespace and bidi/format marks. Go's \s is ASCII-only, so Arabic-mode
	// input can carry a non-breaking space (U+00A0) or a bidirectional mark
	// (U+200E/U+200F/U+202A–202E) that would otherwise survive and make the
	// same number look like a different string (the "Arabic spacing" duplicate
	// bug). \p{Z} = all Unicode separators; \p{Cf} = format/bidi/zero-width.
	phoneStripRE = regexp.MustCompile(`[\s\p{Z}\p{Cf}\-\(\)\.]+`)
	digitsOnlyRE = regexp.MustCompile(`^\d+$`)
)

// iraqDialCode is the default country code assumed when the input carries no
// explicit "+"/"00" international prefix — Iraq stays the implicit default
// (Note #39) so existing Iraqi users typing "0750...", "750...", etc. keep
// working exactly as before, while other countries are now also supported.
const iraqDialCode = "964"

// NormalizePhone collapses every way a phone number can be written into ONE
// canonical form stored in the DB: <country dial code><national number>,
// digits only, no "+", no leading trunk "0" — e.g. an Iraqi number becomes
// "9647508582031". This is also exactly the format OTPIQ expects.
//
// Bare local input (no "+"/dial code) is assumed to be Iraqi, same as
// before:
//
//	7508582031        0750 858 2031     07508582031     9647508582031
//
// all map to "9647508582031". Input with an explicit "+" or "00"
// international prefix is treated as an already country-coded international
// number and passed through digits-only after a basic E.164 range check:
//
//	+1 202 555 0182    00447700900000
//
// map to "12025550182" and "447700900000" respectively.
//
// Returns "" when the input can't be reduced to a valid number (callers
// treat "" as "invalid phone").
func NormalizePhone(raw string) string {
	p := strings.TrimSpace(raw)
	if p == "" {
		return ""
	}
	p = phoneStripRE.ReplaceAllString(p, "")

	explicitCountryCode := false
	if strings.HasPrefix(p, "+") {
		p = strings.TrimPrefix(p, "+")
		explicitCountryCode = true
	} else if strings.HasPrefix(p, "00") {
		p = p[2:]
		explicitCountryCode = true
	}
	if p == "" || !digitsOnlyRE.MatchString(p) {
		return ""
	}

	if !explicitCountryCode {
		// Bare input, no "+"/"00" — assume Iraq. Accept either a local
		// number (strip the trunk "0", require a 10-digit NSN) or one that
		// already carries the Iraq dial code with no "+" in front of it.
		if strings.HasPrefix(p, iraqDialCode) {
			if national := strings.TrimPrefix(p, iraqDialCode); len(national) == 10 {
				return iraqDialCode + national
			}
		}
		if national := strings.TrimLeft(p, "0"); len(national) == 10 {
			return iraqDialCode + national
		}
		return ""
	}

	// Explicit "+"/"00" international prefix — already <dialcode><number>.
	// Basic E.164 sanity range: 7-15 digits total (country code + number).
	if len(p) < 7 || len(p) > 15 {
		return ""
	}
	return p
}
