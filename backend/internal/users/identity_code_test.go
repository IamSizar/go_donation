// K21 — a person could not be found by the identity code that names them.
//
// THE SHAPE OF THE GAP
// The client asked to look up a donation / support history by identity code.
// Two things blocked it, and neither was in the app:
//
//  1. The user could never SEE their own code. recipient_code (073),
//     volunteer_code (077) and grantor_code (105) live on user_profiles, and
//     the Account struct the app receives carried none of them — the
//     registration form promises the code is generated automatically and then
//     never shows it.
//  2. Nothing could RESOLVE a code back to a person outside the admin search.
//
// These tests cover this half: the code reaches the account, and a code
// resolves to exactly one user — including the case that matters most, which is
// that a code belonging to nobody resolves to nobody rather than to whoever
// happens to be first.
//
// The DB-backed tests are skipped unless TEST_DATABASE_URL is set (harness in
// grantor_code_test.go). TestPickIdentityCode needs no database.
package users

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Choosing which code is "this account's" ────────────────────────────

// TestPickIdentityCode pins which of the three columns an account reports as
// ITS code. A profile can carry more than one — a recipient who later
// volunteers keeps both — so "the code" has to be a decision, not an accident of
// column order.
func TestPickIdentityCode(t *testing.T) {
	tests := []struct {
		name                          string
		roleID                        int
		recipient, volunteer, grantor string
		want                          string
	}{
		{
			name:    "a donor reports the grantor code",
			roleID:  1,
			grantor: "GR-000123",
			want:    "GR-000123",
		},
		{
			name:      "an eligible recipient reports the recipient code",
			roleID:    2,
			recipient: "ER-000123",
			want:      "ER-000123",
		},
		{
			name:      "a volunteer reports the volunteer code",
			roleID:    3,
			volunteer: "VL-000123",
			want:      "VL-000123",
		},
		{
			// The role's own column wins even when the profile carries others,
			// so the code shown matches the role the account is acting in.
			name:      "the role's own code wins over the others",
			roleID:    3,
			recipient: "ER-000123",
			volunteer: "VL-000123",
			grantor:   "GR-000123",
			want:      "VL-000123",
		},
		{
			// Someone whose role changed keeps the code already written on
			// their paperwork rather than being shown nothing at all.
			name:      "an empty role code falls back to whatever the profile has",
			roleID:    1,
			recipient: "ER-000123",
			want:      "ER-000123",
		},
		{
			name:   "an account with no code reports none",
			roleID: 1,
			want:   "",
		},
		{
			// Staff and guests have no role in the three-role scheme; they are
			// not given a code they never had.
			name:   "an unknown role with no codes reports none",
			roleID: 0,
			want:   "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := pickIdentityCode(tc.roleID, tc.recipient, tc.volunteer, tc.grantor)
			if got != tc.want {
				t.Errorf("pickIdentityCode(role %d) = %q, want %q", tc.roleID, got, tc.want)
			}
		})
	}
}

// ─── The account carries its code ───────────────────────────────────────

// TestAccountCarriesIdentityCode is the first half of K21: the app cannot ask
// about a code it is never told. This is the response /api/profile and
// /api/auth/me return.
func TestAccountCarriesIdentityCode(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()
	uid := makeUser(t, pool, 1)
	if err := s.EnsureGrantorCode(ctx, uid); err != nil {
		t.Fatalf("EnsureGrantorCode: %v", err)
	}

	acc, err := s.GetAccountForClient(ctx, uid)
	if err != nil {
		t.Fatalf("GetAccountForClient: %v", err)
	}
	if acc == nil {
		t.Fatal("GetAccountForClient returned no account")
	}
	want := "GR-" + pad6(uid)
	if acc.IdentityCode != want {
		t.Errorf("account.identity_code = %q, want %q — the user still cannot see their own code",
			acc.IdentityCode, want)
	}
}

// ─── Resolving a code back to a person ──────────────────────────────────

// TestUserIDByIdentityCode is the second half: the lookup the code-scoped
// history endpoint is built on.
func TestUserIDByIdentityCode(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()
	uid := makeUser(t, pool, 1)
	if err := s.EnsureGrantorCode(ctx, uid); err != nil {
		t.Fatalf("EnsureGrantorCode: %v", err)
	}
	code := grantorCodeOf(t, pool, uid)

	got, err := s.UserIDByIdentityCode(ctx, code)
	if err != nil {
		t.Fatalf("UserIDByIdentityCode(%q): %v", code, err)
	}
	if got != uid {
		t.Errorf("UserIDByIdentityCode(%q) = %d, want %d", code, got, uid)
	}
}

// TestUserIDByIdentityCodeIsCaseAndSpaceTolerant covers how a code actually
// arrives: copied off a receipt or a screen and typed back by hand.
func TestUserIDByIdentityCodeIsCaseAndSpaceTolerant(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()
	uid := makeUser(t, pool, 1)
	if err := s.EnsureGrantorCode(ctx, uid); err != nil {
		t.Fatalf("EnsureGrantorCode: %v", err)
	}
	code := grantorCodeOf(t, pool, uid)

	for _, typed := range []string{
		"  " + code + "  ",
		lower(code),
	} {
		got, err := s.UserIDByIdentityCode(ctx, typed)
		if err != nil {
			t.Fatalf("UserIDByIdentityCode(%q): %v", typed, err)
		}
		if got != uid {
			t.Errorf("UserIDByIdentityCode(%q) = %d, want %d", typed, got, uid)
		}
	}
}

// TestUserIDByIdentityCodeRejectsUnknown is the safety half. A lookup that
// matched loosely — a prefix, a partial, an empty string — would hand out
// somebody else's aid history, so "no match" has to be a clean, specific
// answer.
func TestUserIDByIdentityCodeRejectsUnknown(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()

	for _, code := range []string{
		"",             // nothing typed
		"   ",          // whitespace only
		"GR-",          // a prefix, not a code
		"GR-999999999", // well-formed but nobody's
		"%",            // a LIKE wildcard, if the query ever used LIKE
		"' OR 1=1 --",  // the query is parameterized; this is a value
	} {
		got, err := s.UserIDByIdentityCode(ctx, code)
		if !errors.Is(err, ErrCodeNotFound) {
			t.Errorf("UserIDByIdentityCode(%q) = (%d, %v), want ErrCodeNotFound", code, got, err)
		}
		if got != 0 {
			t.Errorf("UserIDByIdentityCode(%q) returned user %d for a code nobody holds", code, got)
		}
	}
}

// lower is a tiny local helper so the test does not pull in strings just for
// one call.
func lower(s string) string {
	out := []rune(s)
	for i, r := range out {
		if r >= 'A' && r <= 'Z' {
			out[i] = r + 32
		}
	}
	return string(out)
}

// compile-time guard that the harness type is what these tests assume.
var _ = func(p *pgxpool.Pool) *Store { return &Store{Pool: p} }
