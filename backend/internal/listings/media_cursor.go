// media_cursor.go — the keyset ("seek") cursor behind pagination on
// GET /api/media.
//
// WHY KEYSET AND NOT OFFSET. The media feed is ordered by
// `COALESCE(event_date, created_at::date) DESC, id DESC`. With OFFSET, a post
// published (or an event date edited) while the reader is half-way down the
// archive shifts every later row by one: page 2 then repeats a post the reader
// already saw, or skips one entirely. A cursor that names the LAST ROW OF THE
// PREVIOUS PAGE has no such drift — the next page is "everything that sorts
// strictly after this row", which is a stable statement no matter what is
// inserted above it. The `id DESC` tiebreaker already in the ORDER BY is what
// makes this safe when several posts share one date: the pair
// (sort_date, id) is unique, so there is exactly one boundary row.
//
// The cursor is OPAQUE to the client on purpose (base64 of a versioned string):
// clients must treat it as a token to hand back, never as something to build,
// so the sort key can change later without breaking installed apps.
package listings

import (
	"encoding/base64"
	"strconv"
	"strings"
	"time"
)

// cursorDateLayout is the calendar-date form of the sort key. The key is
// `COALESCE(event_date, created_at::date)` — a DATE, not a timestamp — so a
// day-precision layout loses nothing.
const cursorDateLayout = "2006-01-02"

// cursorVersion prefixes every token. If the feed's ORDER BY ever changes, a
// new version can be introduced and old tokens rejected (falling back to page
// one) instead of silently paging through the wrong key.
const cursorVersion = "v1"

// mediaCursor is the position of the last row of a delivered page: the row's
// sort date and its id, together the unique boundary in the feed's ordering.
type mediaCursor struct {
	SortDate time.Time
	ID       int64
}

// encodeMediaCursor renders a boundary row as an opaque token.
func encodeMediaCursor(sortDate time.Time, id int64) string {
	raw := cursorVersion + "|" + sortDate.Format(cursorDateLayout) + "|" + strconv.FormatInt(id, 10)
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

// decodeMediaCursor parses a token produced by [encodeMediaCursor].
//
// It returns ok=false — never an error — for anything it cannot read: an empty
// param, junk, a wrong version, a bad date, a non-numeric or non-positive id.
// The caller treats ok=false as "no cursor" and serves PAGE ONE. That is
// deliberate: a stale or hand-mangled cursor must degrade to the top of the
// feed, not to an error screen, and must never reach SQL — the decoded parts
// are bound as query parameters, and a value that fails to parse here is
// simply discarded rather than interpolated anywhere.
func decodeMediaCursor(raw string) (mediaCursor, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return mediaCursor{}, false
	}
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return mediaCursor{}, false
	}
	parts := strings.Split(string(decoded), "|")
	if len(parts) != 3 || parts[0] != cursorVersion {
		return mediaCursor{}, false
	}
	sortDate, err := time.Parse(cursorDateLayout, parts[1])
	if err != nil {
		return mediaCursor{}, false
	}
	id, err := strconv.ParseInt(parts[2], 10, 64)
	if err != nil || id <= 0 {
		return mediaCursor{}, false
	}
	return mediaCursor{SortDate: sortDate, ID: id}, true
}
