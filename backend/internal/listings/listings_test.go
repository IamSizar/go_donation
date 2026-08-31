// listings_test.go — unit tests for the pure helpers in this package.
//
// parsePostTypes backs the `?type=` query param on GET /api/media. It is
// tested directly (rather than through the handler) because it needs no
// database: the whole risk lives in how a raw query string is split.
package listings

import (
	"reflect"
	"testing"
)

func TestParsePostTypes(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want []string
	}{
		{"empty means no filter", "", []string{}},
		{"whitespace only means no filter", "   ", []string{}},
		{"single type is unchanged", "activity", []string{"activity"}},
		{"comma separated list", "activity,news", []string{"activity", "news"}},
		{"spaces around names are trimmed", " activity , news ", []string{"activity", "news"}},
		// A trailing comma must not yield an empty name: post_type = ANY of a
		// list containing "" matches no row, which would silently empty the feed.
		{"trailing comma drops the blank", "activity,", []string{"activity"}},
		{"repeated commas drop the blanks", "activity,,news", []string{"activity", "news"}},
		{"only commas means no filter", ",,,", []string{}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := parsePostTypes(tc.raw)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("parsePostTypes(%q) = %#v, want %#v", tc.raw, got, tc.want)
			}
		})
	}
}
