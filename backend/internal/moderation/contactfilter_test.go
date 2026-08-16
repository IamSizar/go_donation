// contactfilter_test.go — can two supervised parties still swap a phone
// number or an email address past the filter (K19)?
//
// # WHY THIS EXISTS
//
// K19's supervised donor↔beneficiary thread has always been readable by
// staff, but nothing stopped the two parties agreeing to carry on somewhere
// the supervision cannot reach. The client's words for the risk are
// "منعاً للابتزاز" — to prevent extortion — and a number that leaves the
// thread is the whole exposure.
//
// # WHAT THESE PIN
//
// Two halves, and the second is the one that actually decides whether the
// filter is worth shipping:
//
//   - The BYPASSES are closed. A filter that only knows Latin digits is
//     defeated by an Arabic keyboard in one keystroke, and one that only
//     knows unbroken runs is defeated by a space. Both are worse than no
//     filter at all, because they look like protection. Arabic-Indic and
//     extended Arabic-Indic digits, mixed scripts, separators, and the
//     zero-width/bidi marks that internal/auth/phone.go already learned
//     about the hard way are all pinned here.
//   - The FALSE POSITIVES survive. A donation amount, a case reference, a
//     date and a date range are all digit runs, and a filter that eats them
//     makes the chat unusable for its actual purpose. These are pinned as
//     hard as the bypasses.
//
// Pure string logic — no database, so this runs everywhere.
package moderation

import "testing"

// ─── Bypasses that must be CAUGHT ───────────────────────────────────────

func TestScanContact_BlocksIraqiMobileShapes(t *testing.T) {
	// Every way the same Iraqi mobile number can reach the input box. The
	// national (07…), bare-dial-code (9647…), "+" and "00" international
	// forms are the four the client's own users actually type — they are the
	// same four internal/auth/phone.go accepts on the login screen.
	cases := map[string]string{
		"plain national":       "07701234567",
		"spaced":               "0770 123 4567",
		"dashed":               "0770-123-4567",
		"dotted":               "0770.123.4567",
		"spaced dashes":        "0770 - 123 - 4567",
		"parenthesised":        "(0770) 123 4567",
		"plus dial code":       "+9647701234567",
		"plus spaced":          "+964 770 123 4567",
		"bare dial code":       "9647701234567",
		"double-zero prefix":   "009647701234567",
		"inside a sentence":    "call me on 07701234567 please",
		"arabic sentence":      "رقمي هو 07701234567 اتصل بي",
		"trailing punctuation": "my number is 0770 123 4567.",
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			got := ScanContact(body)
			if !got.Blocked() {
				t.Fatalf("ScanContact(%q) allowed it through; want blocked", body)
			}
			if got.Kind != ContactPhone {
				t.Fatalf("ScanContact(%q).Kind = %q, want %q", body, got.Kind, ContactPhone)
			}
		})
	}
}

func TestScanContact_BlocksNonLatinDigits(t *testing.T) {
	// THE bypass. An Arabic or Kurdish keyboard emits U+0660–0669
	// (Arabic-Indic) or U+06F0–06F9 (extended Arabic-Indic, the Persian/Urdu
	// set); a filter that only reads ASCII digits is defeated without the
	// sender even trying. Mixed script is included because a number typed
	// half on each keyboard is not a hypothetical — it is what happens when
	// autocorrect switches layouts mid-number.
	cases := map[string]string{
		"arabic-indic":          "٠٧٧٠١٢٣٤٥٦٧",
		"arabic-indic spaced":   "٠٧٧٠ ١٢٣ ٤٥٦٧",
		"extended arabic-indic": "۰۷۷۰۱۲۳۴۵۶۷",
		"mixed latin/arabic":    "0770١٢٣4567",
		"arabic-indic +964":     "+٩٦٤٧٧٠١٢٣٤٥٦٧",
		"in an arabic sentence": "رقمي ٠٧٧٠١٢٣٤٥٦٧",
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			if got := ScanContact(body); !got.Blocked() {
				t.Fatalf("ScanContact(%q) allowed it through; want blocked", body)
			}
		})
	}
}

func TestScanContact_BlocksInvisibleCharacterEvasion(t *testing.T) {
	// internal/auth/phone.go carries a regression test for exactly these
	// characters, because Arabic-mode input really does arrive carrying
	// them. Here they are an evasion rather than an accident: a zero-width
	// joiner between two digits is invisible to the recipient and fatal to a
	// naive filter.
	cases := map[string]string{
		"zero-width joiner":  "077‍01234567",
		"zero-width space":   "0770​1234567",
		"non-breaking space": "0770 123 4567",
		"bidi marks":         "‏07701234567‎",
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			if got := ScanContact(body); !got.Blocked() {
				t.Fatalf("ScanContact(%q) allowed it through; want blocked", body)
			}
		})
	}
}

func TestScanContact_BlocksEmail(t *testing.T) {
	cases := map[string]string{
		"plain":            "ahmad@example.com",
		"in a sentence":    "email me at ahmad.karim@example.co.uk thanks",
		"spaced around at": "ahmad @ example . com",
		"plus addressing":  "ahmad+donations@example.com",
		"uppercase":        "AHMAD@EXAMPLE.COM",
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			got := ScanContact(body)
			if !got.Blocked() {
				t.Fatalf("ScanContact(%q) allowed it through; want blocked", body)
			}
			if got.Kind != ContactEmail {
				t.Fatalf("ScanContact(%q).Kind = %q, want %q", body, got.Kind, ContactEmail)
			}
		})
	}
}

func TestScanContact_ReportsBothWhenBothPresent(t *testing.T) {
	got := ScanContact("07701234567 or ahmad@example.com")
	if got.Kind != ContactBoth {
		t.Fatalf("Kind = %q, want %q", got.Kind, ContactBoth)
	}
	if got.Count != 2 {
		t.Fatalf("Count = %d, want 2", got.Count)
	}
}

// ─── False positives that must SURVIVE ──────────────────────────────────

func TestScanContact_AllowsLegitimateDigitRuns(t *testing.T) {
	// The reason this filter refuses rather than silently strips: everything
	// here is a digit run a real message needs to carry. If the filter eats
	// a donation amount or a case reference, the supervised chat stops being
	// usable for the thing it exists to do, and staff turn it off.
	//
	// The shapes are taken from the codebase, not invented: sectioncodes
	// issues "CAM-000042"-style references, and amounts are plain integers.
	cases := map[string]string{
		"small amount":          "250000",
		"grouped amount":        "1,000,000 IQD",
		"large amount":          "The campaign raised 25,000,000 dinars",
		"ten-digit amount":      "1234567890",
		"section reference":     "CAM-000042",
		"case code":             "CSE-2026-001",
		"iso date":              "2026-08-16",
		"slashed date":          "16/08/2026",
		"dotted date":           "16.08.2026",
		"date range":            "07-01-2026 to 07-05-2026",
		"year":                  "we started in 2026",
		"percentage":            "we reached 85% of the goal",
		"time":                  "meet at 14:30",
		"plain arabic text":     "شكراً جزيلاً على تبرعكم الكريم",
		"plain english text":    "Thank you so much for your generous donation",
		"arabic-indic amount":   "٢٥٠٠٠٠ دينار",
		"arabic-indic date":     "٢٠٢٦-٠٨-١٦",
		"quantity list":         "5 blankets, 12 food baskets, 30 blankets",
		"empty":                 "",
		"receipt-ish reference": "Receipt no. 000042",
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			if got := ScanContact(body); got.Blocked() {
				t.Fatalf("ScanContact(%q) was blocked as %q; it must survive", body, got.Kind)
			}
		})
	}
}

// ─── Redaction of the supervision record ────────────────────────────────

func TestScanContact_RedactedHidesTheNumber(t *testing.T) {
	// The attempt is recorded for staff so a REPEATED attempt is visible —
	// the pattern is the extortion signal. What is deliberately NOT recorded
	// is the number itself: storing it would turn the supervision log into
	// the exact directory of smuggled contact details the row exists to
	// prevent.
	got := ScanContact("call me on 07701234567 please")
	if !got.Blocked() {
		t.Fatal("expected blocked")
	}
	if got.Redacted == "" {
		t.Fatal("Redacted is empty; staff need the surrounding context")
	}
	for _, leak := range []string{"07701234567", "0770", "1234567"} {
		if contains(got.Redacted, leak) {
			t.Fatalf("Redacted = %q still leaks %q", got.Redacted, leak)
		}
	}
	if !contains(got.Redacted, "call me on") {
		t.Fatalf("Redacted = %q dropped the surrounding context", got.Redacted)
	}
}

func contains(haystack, needle string) bool {
	if len(needle) > len(haystack) {
		return false
	}
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
