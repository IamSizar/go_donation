package handlers

import "testing"

// The row that blanked the City Guide map for every user carried latitude 500,
// longitude 700. The app now refuses to plot it; this is the other half —
// it should never have been storable.
func TestValidateCoordinate(t *testing.T) {
	cases := []struct {
		name     string
		lat, lng string
		wantErr  bool
	}{
		{"the exact production row", "500.0000000", "700.0000000", true},
		{"latitude past the pole", "90.1", "43.1", true},
		{"latitude past the south pole", "-90.1", "43.1", true},
		{"longitude past the antimeridian", "36.3", "180.1", true},
		{"not a number", "abc", "43.1", true},
		{"NaN", "NaN", "43.1", true},
		{"infinity", "Inf", "43.1", true},
		// Half a coordinate cannot be plotted, and storing it hides the
		// mistake until somebody opens the map.
		{"latitude without longitude", "36.3", "", true},
		{"longitude without latitude", "", "43.1", true},

		{"Mosul", "36.3489", "43.1489", false},
		{"the poles exactly", "90", "180", false},
		{"the other extreme", "-90", "-180", false},
		{"southern hemisphere", "-33.86", "151.2", false},
		// Most entries have no location at all; requiring one would reject
		// them.
		{"no location at all", "", "", false},
		{"whitespace is not a location", "  ", "  ", false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := validateCoordinate(tc.lat, tc.lng)
			if tc.wantErr && got == "" {
				t.Errorf("validateCoordinate(%q, %q) accepted it; want a refusal",
					tc.lat, tc.lng)
			}
			if !tc.wantErr && got != "" {
				t.Errorf("validateCoordinate(%q, %q) refused it: %s",
					tc.lat, tc.lng, got)
			}
		})
	}
}

// The message has to name the field and the offending value: a staff member
// who typed 500 into a box needs to know which box and why.
func TestValidateCoordinateExplainsItself(t *testing.T) {
	msg := validateCoordinate("500", "43.1")
	if msg == "" {
		t.Fatal("expected a refusal")
	}
	for _, want := range []string{"latitude", "500"} {
		if !contains(msg, want) {
			t.Errorf("message %q does not mention %q", msg, want)
		}
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (func() bool {
		for i := 0; i+len(sub) <= len(s); i++ {
			if s[i:i+len(sub)] == sub {
				return true
			}
		}
		return false
	})()
}
