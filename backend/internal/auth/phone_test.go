package auth

import "testing"

func TestNormalizePhone(t *testing.T) {
	const canon = "07508582031"
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

		// Section 27 — leading/trailing/duplicate ASCII spaces plus Arabic-mode
		// invisible characters must all collapse to the same canonical value:
		// non-breaking space (U+00A0), bidi marks (U+200E/U+200F), and
		// zero-width joiner (U+200D). Built with \u escapes so the source stays
		// ASCII and the intent is unambiguous.
		"  0750  858  2031  ":                            canon, // leading/trailing/duplicate spaces
		"0750 858 2031":                        canon, // non-breaking spaces
		"‏0750 858 2031‎":                      canon, // RTL/LTR bidi marks
		"0750858‍2031":                              canon, // zero-width joiner

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
	for _, in := range []string{"07508582031", "07700000001"} {
		once := NormalizePhone(in)
		twice := NormalizePhone(once)
		if once != in || twice != once {
			t.Errorf("not idempotent for %q: once=%q twice=%q", in, once, twice)
		}
	}
}
