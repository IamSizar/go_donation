package auth

import "testing"

func TestNormalizePhone(t *testing.T) {
	const canon = "9647508582031"
	cases := map[string]string{
		// Every accepted way to write the same Iraqi mobile → one canonical value.
		"7508582031":         canon,
		"07508582031":        canon,
		"750 858 2031":       canon,
		"0750 858 2031":      canon,
		"0750-858-2031":      canon,
		"(0750) 858 2031":    canon,
		"+9647508582031":     canon,
		"+964 750 858 2031":  canon,
		"9647508582031":      canon,
		"00964 750 858 2031": canon,
		"964 750 858 2031":   canon,

		// #39 — international numbers (explicit "+"/"00" prefix) pass through
		// digits-only, no longer hard-rejected as Iraq-only.
		"+1 202 555 0182": "12025550182",
		"+44 7700 900000": "447700900000",
		"00447700900000":  "447700900000",
		"+9661234567":     "9661234567",

		// Section 27 — leading/trailing/duplicate ASCII spaces plus Arabic-mode
		// invisible characters must all collapse to the same canonical value:
		// non-breaking space (U+00A0), bidi marks (U+200E/U+200F), and
		// zero-width joiner (U+200D). Built with \u escapes so the source stays
		// ASCII and the intent is unambiguous.
		"  0750  858  2031  ": canon, // leading/trailing/duplicate spaces
		"0750 858 2031":       canon, // non-breaking spaces
		"‏0750 858 2031‎":     canon, // RTL/LTR bidi marks
		"0750858‍2031":        canon, // zero-width joiner

		// OPOS #25268 — the app always sends the dial code explicitly (the
		// country picker prepends "+964"), so an Iraqi submission goes
		// through THIS branch, not the bare-input one above. Before the fix,
		// this used the generic 7-15-total-digit E.164 range instead of
		// Iraq's own exact 10-digit national-number rule, so a 9-digit
		// national number like this reported one was wrongly accepted.
		"+964773800028":   "",              // 9-digit NSN with explicit dial code — reported bug
		"+9647738000289":  "9647738000289", // corrected to 10 digits — must still work
		"+96477380002891": "",              // 11-digit NSN with explicit dial code — too long

		// Invalid → "".
		"":            "",
		"   ":         "",
		"abc":         "",
		"123":         "", // too short
		"750858203":   "", // 9-digit NSN
		"75085820311": "", // 11-digit NSN
		"hello 750":   "",
	}
	for in, want := range cases {
		if got := NormalizePhone(in); got != want {
			t.Errorf("NormalizePhone(%q) = %q, want %q", in, got, want)
		}
	}
}

// Idempotence: normalizing an already-canonical value returns it unchanged.
func TestNormalizePhoneIdempotent(t *testing.T) {
	for _, in := range []string{"9647508582031", "9647700000001"} {
		once := NormalizePhone(in)
		twice := NormalizePhone(once)
		if once != in || twice != once {
			t.Errorf("not idempotent for %q: once=%q twice=%q", in, once, twice)
		}
	}
}
