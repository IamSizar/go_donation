package auth

import (
	"regexp"
	"strings"
)

var (
	// Strip human formatting: spaces, dashes, parens, dots.
	phoneStripRE = regexp.MustCompile(`[\s\-\(\)\.]+`)
	digitsOnlyRE = regexp.MustCompile(`^\d+$`)
)

// NormalizePhone collapses every way an Iraqi mobile number can be written into
// ONE canonical form stored in the DB: a leading "0" followed by the 10-digit
// national number, e.g. "07508582031".
//
// All of these map to "07508582031":
//
//	7508582031        0750 858 2031     07508582031
//	+964 750 858 2031  9647508582031    00964 750 858 2031
//
// This is what prevents the "0750…" vs "750…" (and "+964…") duplicate-account
// bug: login + OTP all run input through here, so the same human is always the
// same row regardless of how they typed it.
//
// Returns "" when the input doesn't reduce to a 10-digit national number
// (callers treat "" as "invalid phone").
func NormalizePhone(raw string) string {
	p := strings.TrimSpace(raw)
	if p == "" {
		return ""
	}
	p = phoneStripRE.ReplaceAllString(p, "")
	p = strings.TrimPrefix(p, "+")
	// "00" is the international call prefix (e.g. 00964…) — drop it so the
	// country code is handled uniformly below.
	if strings.HasPrefix(p, "00") {
		p = p[2:]
	}
	if p == "" || !digitsOnlyRE.MatchString(p) {
		return ""
	}
	// Drop the Iraq country code if present, then any national trunk "0".
	// Iraqi mobile NSNs start with 7, so a real 10-digit NSN never begins
	// with "964" — stripping it here is safe.
	p = strings.TrimPrefix(p, "964")
	p = strings.TrimLeft(p, "0")
	if len(p) != 10 {
		return ""
	}
	return "0" + p
}
