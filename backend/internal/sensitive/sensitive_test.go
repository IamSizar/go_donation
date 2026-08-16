// sensitive_test.go — the two properties every H10 call site depends on.
//
// These need no database, so they run on a bare checkout. That matters: they
// pin the ONE invariant the whole feature rests on — anything Mask produces,
// IsMasked recognises — and if that ever stopped holding, the redaction would
// keep working while the write guard silently stopped, which is the exact
// failure mode that destroys sign-in numbers.
package sensitive

import "testing"

// TestMaskIsAlwaysRecognisable is the load-bearing property. Every value here
// is a shape real contact data actually takes in this database.
func TestMaskIsAlwaysRecognisable(t *testing.T) {
	values := []string{
		"9647500000903",     // an Iraqi mobile in the canonical sign-in form
		"07508582031",       // the same number as an operator types it
		"donor@example.com", // an email
		"+964 750 858 2031", // a formatted contact number
		"a@b.co",            // the shortest plausible email
		"7",                 // a single character — the <=2 branch
		"12",                // exactly the kept length
		"٠٧٥٠٨٥٨٢٠٣١",       // Arabic-Indic digits, which this app accepts
		"مكتب أربيل ٠٧٥٠",   // a value with non-ASCII and a space
	}
	for _, v := range values {
		masked := Mask(v)
		if masked == v {
			t.Errorf("Mask(%q) returned the value unchanged — nothing was redacted", v)
		}
		if !IsMasked(masked) {
			t.Errorf("IsMasked(Mask(%q)) = false — the write guard would let %q through and store it", v, masked)
		}
		if IsMasked(v) {
			t.Errorf("IsMasked(%q) = true on a REAL value — legitimate edits would be refused", v)
		}
	}
}

// TestMaskLeavesEmptyAlone — a blank column is not a secret. Masking it would
// invent a value the record does not hold, and an operator would read "••" and
// go looking for a number nobody ever gave.
func TestMaskLeavesEmptyAlone(t *testing.T) {
	if got := Mask(""); got != "" {
		t.Errorf("Mask(\"\") = %q, want \"\"", got)
	}
	if IsMasked("") {
		t.Error("IsMasked(\"\") = true — an empty PATCH field would be refused")
	}
	if got := MaskPtr(nil); got != nil {
		t.Error("MaskPtr(nil) invented a value for a SQL NULL")
	}
}

// TestMaskKeepsATailButNoMore — the hint exists so staff can confirm a number
// somebody just read out to them. It must not be long enough to be useful on
// its own, and it must not be as long as the value it hides.
func TestMaskKeepsATailButNoMore(t *testing.T) {
	if got, want := Mask("9647500000903"), "••••03"; got != want {
		t.Errorf("Mask = %q, want %q", got, want)
	}
	// Two characters or fewer: a hint the same length as the value is not a
	// hint, so the tail is dropped entirely.
	for _, short := range []string{"7", "12"} {
		if got, want := Mask(short), "••"; got != want {
			t.Errorf("Mask(%q) = %q, want %q", short, got, want)
		}
	}
}

// TestMaskAnyPassesNonStringsThrough — pgx row maps carry ints, times and nils
// alongside text. Stringifying those to mask them would corrupt the JSON shape
// the dashboard parses.
func TestMaskAnyPassesNonStringsThrough(t *testing.T) {
	if got := MaskAny(nil); got != nil {
		t.Errorf("MaskAny(nil) = %v, want nil", got)
	}
	if got := MaskAny(42); got != 42 {
		t.Errorf("MaskAny(42) = %v, want 42", got)
	}
	if got, want := MaskAny("9647500000903"), "••••03"; got != want {
		t.Errorf("MaskAny = %v, want %q", got, want)
	}
}

// TestProseIsNotAMask is the reason the write guard is scoped to contact fields
// instead of sweeping whole request bodies: staff write bulleted lists into
// free text, and a mask test cannot tell those apart.
func TestProseIsNotAMask(t *testing.T) {
	notes := "• سكن غير ملائم\n• دخل شهري منخفض"
	if !IsMasked(notes) {
		t.Fatal("this test is documenting that IsMasked DOES match prose bullets — " +
			"if that changed, the per-field scoping comment needs updating too")
	}
}
