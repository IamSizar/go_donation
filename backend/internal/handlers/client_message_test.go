// client_message_test.go — what may and may not reach an operator's screen.
//
// The machine-text cases are taken from what these handlers actually produce:
// pgx wraps every Postgres failure with a SQLSTATE, and the stores below the
// handlers return those raw on their fallthrough path (`return nil, err` after
// the duplicate check). The human cases are the real strings the same stores
// write for people, which must survive untouched — a sanitizer that swallowed
// "a category with that name already exists" would replace a precise message
// with a vague one and make the screen worse.
package handlers

import (
	"errors"
	"strings"
	"testing"
)

func TestClientMessageWithholdsMachineText(t *testing.T) {
	for _, tc := range []struct {
		name string
		in   string
	}{
		{
			"postgres not-null violation",
			`ERROR: null value in column "name_ar" violates not-null constraint (SQLSTATE 23502)`,
		},
		{
			"postgres unique violation naming an index",
			`ERROR: duplicate key value violates unique constraint "idx_users_username" (SQLSTATE 23505)`,
		},
		{"pgx no rows", "no rows in result set"},
		{"database/sql sentinel", "sql: no rows in result set"},
		{"json type mismatch", "json: cannot unmarshal string into Go struct field .Age of type int"},
		{"json syntax", "invalid character '}' looking for beginning of object key string"},
		{"lost connection", "failed to connect to `host=db`: dial tcp 10.0.0.4:5432: connect: connection refused"},
		{"timeout", "context deadline exceeded"},
		{"recovered panic", "runtime error: invalid memory address or nil pointer dereference"},
		{"error carrying a source location", "handlers/admin_city_categories.go:59: bad input"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := clientMessage(errors.New(tc.in))
			if got != genericClientMessage {
				t.Errorf("machine text reached the operator:\n  in:  %s\n  out: %s", tc.in, got)
			}
		})
	}
}

// The whole point of not replacing everything: these were written to be read.
func TestClientMessageKeepsMessagesWrittenForPeople(t *testing.T) {
	for _, in := range []string{
		"English name is required",
		"a category with that name already exists",
		"category not found",
		"could not derive a category key",
		"A user with this phone already exists.",
		"Username must be 3-64 characters, using only letters, digits, dot, underscore or hyphen.",
		"كلمة المرور مطلوبة للمتابعة.",
	} {
		t.Run(in, func(t *testing.T) {
			if got := clientMessage(errors.New(in)); got != in {
				t.Errorf("human message was replaced:\n  in:  %s\n  out: %s", in, got)
			}
		})
	}
}

// A wrapped chain can open with a human-looking clause and carry the driver's
// text in its tail, which is exactly the case a "does it start nicely?" check
// would wave through.
func TestClientMessageWithholdsWrappedChains(t *testing.T) {
	wrapped := errors.New("saving the category: inserting row: " +
		`ERROR: duplicate key value violates unique constraint "city_categories_slug_key" (SQLSTATE 23505)`)
	if got := clientMessage(wrapped); got != genericClientMessage {
		t.Errorf("wrapped chain leaked: %s", got)
	}
}

func TestClientMessageWithholdsOverlongAndMultilineText(t *testing.T) {
	long := errors.New(strings.Repeat("a", maxClientMessageRunes+1))
	if got := clientMessage(long); got != genericClientMessage {
		t.Errorf("overlong text passed through: %s", got)
	}
	multi := errors.New("something failed\n\tat some.internal.frame")
	if got := clientMessage(multi); got != genericClientMessage {
		t.Errorf("multiline text passed through: %q", got)
	}
}

// A blank `error` field renders as an empty toast, which reads as the dashboard
// failing silently — worse than a vague sentence.
func TestClientMessageNeverReturnsEmpty(t *testing.T) {
	for _, err := range []error{nil, errors.New(""), errors.New("   ")} {
		if got := clientMessage(err); strings.TrimSpace(got) == "" {
			t.Errorf("clientMessage(%v) returned empty", err)
		}
	}
}

// The marker match must not depend on how the driver happened to capitalise.
func TestClientMessageMatchesMarkersRegardlessOfCase(t *testing.T) {
	for _, in := range []string{
		"ERROR: ... (SQLSTATE 23505)",
		"error: ... (sqlstate 23505)",
		"Violates Unique Constraint",
	} {
		if got := clientMessage(errors.New(in)); got != genericClientMessage {
			t.Errorf("case variant leaked: %s", got)
		}
	}
}
