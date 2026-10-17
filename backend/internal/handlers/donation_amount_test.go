package handlers

import "testing"

// R2 #54 — a dinar-sized gift must be accepted, and an unusable amount must be
// refused instead of being saved as an empty row.
func TestParseIQDAmount(t *testing.T) {
	cases := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"50000", 50000, true},
		{"1000000", 1000000, true},
		{"25000000", 25000000, true},
		{" 7500 ", 7500, true},
		{"0", 0, false},
		{"-5", 0, false},
		{"abc", 0, false},
		{"", 0, false},
		{"2000000000", 0, false},
	}
	for _, c := range cases {
		got, ok := parseIQDAmount(c.in)
		if ok != c.ok || got != c.want {
			t.Errorf("parseIQDAmount(%q) = %d,%v want %d,%v", c.in, got, ok, c.want, c.ok)
		}
	}
}
