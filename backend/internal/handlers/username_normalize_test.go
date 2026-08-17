// username_normalize_test.go — the rules a dashboard sign-in name must satisfy
// before it reaches the database.
//
// These cover normalizeUsername alone, with no pool: the point of extracting it
// was that the interesting decisions (case folding, the character set, blank
// meaning "no dashboard access" rather than "error") are pure and can be proved
// without a database, unlike CreateUser itself.
//
// The case-folding cases are the ones that matter. Folding at write time is
// what keeps GetByUsername's case-insensitive lookup single-valued — if a
// capitalised name could be stored, "Supervisor" and "supervisor" could both
// exist and a password would be checked against whichever row sorted first.
package handlers

import "testing"

func strPtr(s string) *string { return &s }

func TestNormalizeUsernameFoldsAndTrims(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"already canonical", "supervisor", "supervisor"},
		{"capitalised by a phone keyboard", "Supervisor", "supervisor"},
		{"shouted", "SUPERVISOR", "supervisor"},
		{"padded by a paste", "  supervisor  ", "supervisor"},
		{"dots and hyphens are allowed", "a.b-c_1", "a.b-c_1"},
		{"exactly at the length ceiling", string(make([]byte, 0, 64)) + repeat("a", 64), repeat("a", 64)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := normalizeUsername(strPtr(tc.in))
			if err != nil {
				t.Fatalf("normalizeUsername(%q) returned error: %v", tc.in, err)
			}
			if got != tc.want {
				t.Errorf("normalizeUsername(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

// Absent and blank are not errors: the credential pair is optional, and most
// accounts the dashboard creates are app users who will never sign in here.
func TestNormalizeUsernameTreatsAbsentAndBlankAsUnset(t *testing.T) {
	for _, tc := range []struct {
		name string
		in   *string
	}{
		{"field omitted entirely", nil},
		{"empty box", strPtr("")},
		{"whitespace only", strPtr("   ")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := normalizeUsername(tc.in)
			if err != nil {
				t.Fatalf("expected no error, got %v", err)
			}
			if got != "" {
				t.Errorf("expected empty username, got %q", got)
			}
		})
	}
}

func TestNormalizeUsernameRejectsUnusableNames(t *testing.T) {
	for _, tc := range []struct {
		name string
		in   string
	}{
		{"too short to be distinctive", "ab"},
		// VARCHAR(64) — one over is a database error rather than a message.
		{"one past the column width", repeat("a", 65)},
		{"inner space", "super visor"},
		{"at sign", "super@visor"},
		{"slash", "super/visor"},
		{"arabic digits", "مستخدم"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := normalizeUsername(strPtr(tc.in)); err == nil {
				t.Errorf("normalizeUsername(%q) was accepted; expected rejection", tc.in)
			}
		})
	}
}

func repeat(s string, n int) string {
	out := make([]byte, 0, len(s)*n)
	for i := 0; i < n; i++ {
		out = append(out, s...)
	}
	return string(out)
}
