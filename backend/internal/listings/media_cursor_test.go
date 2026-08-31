// media_cursor_test.go — the keyset pagination behind GET /api/media.
//
// These are pure-function tests on purpose: the cursor round-trip and the
// limit+1 trim are where a paging bug actually lives (a repeated post, a
// skipped post, an error page from a stale token), and none of that needs a
// database to reproduce. The SQL boundary predicate itself is exercised
// against the real database by hand — see the commit body.
package listings

import (
	"encoding/base64"
	"testing"
	"time"
)

func day(s string) time.Time {
	t, err := time.Parse(cursorDateLayout, s)
	if err != nil {
		panic(err)
	}
	return t
}

func TestMediaCursorRoundTrip(t *testing.T) {
	token := encodeMediaCursor(day("2024-03-09"), 412)
	got, ok := decodeMediaCursor(token)
	if !ok {
		t.Fatalf("decodeMediaCursor(%q) = not ok, want ok", token)
	}
	if !got.SortDate.Equal(day("2024-03-09")) || got.ID != 412 {
		t.Fatalf("round trip = %v/%d, want 2024-03-09/412", got.SortDate, got.ID)
	}
}

// A cursor the server did not mint must degrade to PAGE ONE, never to an
// error and never into SQL. Every case here is something a real client can
// send: a missing param, a truncated token, a hand-edited one.
func TestMediaCursorFallsBackToPageOne(t *testing.T) {
	cases := []struct {
		name string
		raw  string
	}{
		{"empty means no cursor", ""},
		{"whitespace means no cursor", "   "},
		{"not base64", "!!!not-base64!!!"},
		{"base64 of junk", b64("hello")},
		{"wrong field count", b64("v1|2024-03-09")},
		{"unknown version", b64("v2|2024-03-09|412")},
		{"unparseable date", b64("v1|09-03-2024|412")},
		{"non numeric id", b64("v1|2024-03-09|abc")},
		{"zero id is not a real row", b64("v1|2024-03-09|0")},
		{"negative id is not a real row", b64("v1|2024-03-09|-5")},
		// A SQL fragment is just an unparseable id here; it is dropped at the
		// door and never reaches the query, which binds parameters anyway.
		{"sql in the id is discarded", b64("v1|2024-03-09|1 OR 1=1")},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, ok := decodeMediaCursor(tc.raw); ok {
				t.Fatalf("decodeMediaCursor(%q) = ok, want fallback to page one", tc.raw)
			}
		})
	}
}

// TestTrimMediaPageNoCursorMatchesTodaysBehaviour: a full result set that fits
// within the limit is handed back untouched and promises no next page — which
// is exactly what the endpoint did before pagination existed.
func TestTrimMediaPageEndOfArchive(t *testing.T) {
	items := postsOn("2024-05-01", 3, 2, 1)
	got, next, err := trimMediaPage(items, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 {
		t.Fatalf("len = %d, want 3 rows unchanged", len(got))
	}
	if next != "" {
		t.Fatalf("next cursor = %q, want empty at the end of the archive", next)
	}
}

// The probe row (limit+1) must never be delivered, and the cursor must name
// the LAST DELIVERED row — not the probe. Cursoring off the probe would skip
// exactly one post at every page break.
func TestTrimMediaPageDropsTheProbeRow(t *testing.T) {
	items := postsOn("2024-05-01", 9, 8, 7)
	got, next, err := trimMediaPage(items, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].ID != 9 || got[1].ID != 8 {
		t.Fatalf("page = %v, want ids 9,8", ids(got))
	}
	cur, ok := decodeMediaCursor(next)
	if !ok {
		t.Fatalf("next cursor %q did not decode", next)
	}
	if cur.ID != 8 {
		t.Fatalf("cursor id = %d, want 8 (the last DELIVERED row, not the probe)", cur.ID)
	}
}

// TestPagesDoNotOverlapOrSkip walks a fixed archive page by page the way the
// app does, using the same boundary predicate the SQL uses, and asserts the
// concatenation of the pages is the archive exactly once.
//
// The archive deliberately puts THREE posts on one date: the date alone cannot
// separate them, so this is the test of the `id DESC` tiebreaker. Drop the id
// half of the comparison and posts 21 and 20 are either both re-served on
// page 2 or both lost.
func TestPagesDoNotOverlapOrSkip(t *testing.T) {
	archive := []MediaPost{
		{ID: 30, sortDate: day("2024-06-01")},
		{ID: 22, sortDate: day("2024-05-20")},
		{ID: 21, sortDate: day("2024-05-20")},
		{ID: 20, sortDate: day("2024-05-20")},
		{ID: 11, sortDate: day("2024-04-02")},
		{ID: 10, sortDate: day("2024-04-02")},
		{ID: 3, sortDate: day("2024-01-15")},
	}
	const perPage = 2

	seen := []int64{}
	cursor := ""
	for page := 0; ; page++ {
		if page > 10 {
			t.Fatal("paging did not terminate")
		}
		window := afterCursor(archive, cursor, perPage+1)
		got, next, err := trimMediaPage(window, perPage)
		if err != nil {
			t.Fatal(err)
		}
		seen = append(seen, ids(got)...)
		if next == "" {
			break
		}
		cursor = next
	}

	want := ids(archive)
	if len(seen) != len(want) {
		t.Fatalf("paged through %v, want %v", seen, want)
	}
	for i := range want {
		if seen[i] != want[i] {
			t.Fatalf("paged through %v, want %v (order/overlap/skip)", seen, want)
		}
	}
}

// ----------------- helpers -----------------

// b64 builds a token body the way the encoder would, so a test case can pin a
// malformed PAYLOAD rather than merely malformed base64.
func b64(s string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(s))
}

// afterCursor is the in-memory twin of the SQL boundary predicate
//
//	(COALESCE(event_date, created_at::date), id) < ($date, $id)
//
// over an already-sorted archive, so the paging walk above tests the same rule
// the database applies.
func afterCursor(archive []MediaPost, cursor string, limit int) []MediaPost {
	cur, ok := decodeMediaCursor(cursor)
	out := []MediaPost{}
	for _, m := range archive {
		if ok {
			after := m.sortDate.Before(cur.SortDate) ||
				(m.sortDate.Equal(cur.SortDate) && m.ID < cur.ID)
			if !after {
				continue
			}
		}
		out = append(out, m)
		if len(out) == limit {
			break
		}
	}
	return out
}

func postsOn(date string, idList ...int64) []MediaPost {
	out := make([]MediaPost, 0, len(idList))
	for _, id := range idList {
		out = append(out, MediaPost{ID: id, sortDate: day(date)})
	}
	return out
}

func ids(items []MediaPost) []int64 {
	out := make([]int64, 0, len(items))
	for _, m := range items {
		out = append(out, m.ID)
	}
	return out
}
