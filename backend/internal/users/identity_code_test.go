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

// ─── Minting the code a CHANGED role implies ────────────────────────────

// TestIdentityCodePrefixForRole pins which roles have a code scheme and which
// deliberately have none.
//
// This is the decision the fix turns on, so it is tested without a database —
// the DB-backed tests below skip themselves on a bare checkout, and the rule
// "role 4 gets nothing, and that is not a failure" must be provable anyway.
// Same reason normalizeUsername in internal/handlers/admin_status.go is a plain
// function.
func TestIdentityCodePrefixForRole(t *testing.T) {
	tests := []struct {
		name   string
		roleID int
		want   string
	}{
		{name: "a donor is minted a GR- code", roleID: 1, want: "GR-"},
		{name: "an eligible recipient is minted an ER- code", roleID: 2, want: "ER-"},
		{name: "a volunteer is minted a VL- code", roleID: 3, want: "VL-"},
		{
			// Role 0 is the unassigned/browsing state, before a role is picked
			// and after stepping back to it. There is no column, no prefix and
			// no migration minting one, so there is nothing honest to assign.
			name: "a guest has no code scheme", roleID: 0, want: "",
		},
		{
			// Employees are staff, not one of the three roles the client asked
			// for codes for.
			name: "an employee has no code scheme", roleID: 4, want: "",
		},
		{
			// The marriage/engagement account type is self-selectable
			// (choose_role.go) and likewise carries no code column.
			name: "a marriage account has no code scheme", roleID: 5, want: "",
		},
		{name: "an unknown role has no code scheme", roleID: 99, want: ""},
		{name: "a negative role has no code scheme", roleID: -1, want: ""},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := identityCodePrefixForRole(tc.roleID); got != tc.want {
				t.Errorf("identityCodePrefixForRole(%d) = %q, want %q", tc.roleID, got, tc.want)
			}
		})
	}
}

// TestEnsureIdentityCodeForRoleRejectsInvalidUser is the guard clause, the same
// one every Ensure* helper carries. Silently succeeding on a bad id would hide
// a caller bug at exactly the layer that is supposed to be forgiving about
// failures.
func TestEnsureIdentityCodeForRoleRejectsInvalidUser(t *testing.T) {
	s := &Store{} // no pool needed: the guard returns before any query
	if err := s.EnsureIdentityCodeForRole(context.Background(), 0, 2); err == nil {
		t.Fatal("EnsureIdentityCodeForRole(0, 2) returned nil; want an error")
	}
}

// codesOf reads all three identity columns at once, so the assign-once tests
// can assert both what was written AND what was left alone.
func codesOf(t *testing.T, pool *pgxpool.Pool, userID int64) (recipient, volunteer, grantor string) {
	t.Helper()
	if err := pool.QueryRow(context.Background(),
		`SELECT recipient_code, volunteer_code, grantor_code
		   FROM user_profiles WHERE user_id = $1`, userID,
	).Scan(&recipient, &volunteer, &grantor); err != nil {
		t.Fatalf("read identity codes for %d: %v", userID, err)
	}
	return recipient, volunteer, grantor
}

// TestRecipientCodeIsAssignedOnce is the missing helper's own row. ER- was the
// one code with no Ensure* function: it was minted inline in SubmitRegistration
// and nowhere else, so the only moment the server could ever produce one was a
// registration form submitted as role 2.
func TestRecipientCodeIsAssignedOnce(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	uid := makeUser(t, pool, 2)

	if err := s.EnsureRecipientCode(context.Background(), uid); err != nil {
		t.Fatalf("EnsureRecipientCode: %v", err)
	}
	recipient, _, _ := codesOf(t, pool, uid)
	want := "ER-" + pad6(uid)
	if recipient != want {
		t.Fatalf("recipient got no identity code: recipient_code = %q, want %q", recipient, want)
	}
}

// TestRecipientCodeIsStableOnceAssigned pins the assign-once half, mirroring
// TestGrantorCodeIsStableOnceAssigned. A code is quoted in conversation and
// printed on paperwork; re-minting it on a later role change would stop it
// identifying anybody, and would discard a code an operator set by hand.
func TestRecipientCodeIsStableOnceAssigned(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()
	uid := makeUser(t, pool, 2)

	if _, err := pool.Exec(ctx,
		`UPDATE user_profiles SET recipient_code = 'ER-CUSTOM' WHERE user_id = $1`, uid); err != nil {
		t.Fatalf("seed custom code: %v", err)
	}
	if err := s.EnsureRecipientCode(ctx, uid); err != nil {
		t.Fatalf("EnsureRecipientCode: %v", err)
	}
	if recipient, _, _ := codesOf(t, pool, uid); recipient != "ER-CUSTOM" {
		t.Fatalf("an existing identity code was overwritten: got %q, want %q", recipient, "ER-CUSTOM")
	}
}

// TestEnsureIdentityCodeForRoleMintsTheNewRolesCode is user 58's case, the one
// observed in production: registered as a donor, so the profile carries
// GR-000058; staff later moved the account to role 2. Before the fix the
// account reported role_id 2 with an empty recipient_code, so pickIdentityCode
// fell back to showing a recipient a DONOR's code, and staff searching an ER-
// code could never find them because the searched column was empty.
//
// The old code is kept, not replaced — somebody who has held two roles holds
// two codes, and pickIdentityCode is what decides which one is shown.
func TestEnsureIdentityCodeForRoleMintsTheNewRolesCode(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()
	uid := makeUser(t, pool, 1)

	// They registered as a donor and were given the donor's code.
	if err := s.EnsureGrantorCode(ctx, uid); err != nil {
		t.Fatalf("EnsureGrantorCode: %v", err)
	}
	// Staff move the account to eligible recipient.
	if _, err := pool.Exec(ctx, `UPDATE users SET role_id = 2 WHERE id = $1`, uid); err != nil {
		t.Fatalf("change role: %v", err)
	}
	if err := s.EnsureIdentityCodeForRole(ctx, uid, 2); err != nil {
		t.Fatalf("EnsureIdentityCodeForRole: %v", err)
	}

	recipient, _, grantor := codesOf(t, pool, uid)
	wantRecipient := "ER-" + pad6(uid)
	if recipient != wantRecipient {
		t.Errorf("recipient_code = %q, want %q — no ER- search will ever find this recipient",
			recipient, wantRecipient)
	}
	if wantGrantor := "GR-" + pad6(uid); grantor != wantGrantor {
		t.Errorf("grantor_code = %q, want %q — the code already on their paperwork was destroyed",
			grantor, wantGrantor)
	}
	// And the account now reports the code its CURRENT role implies.
	if got := pickIdentityCode(2, recipient, "", grantor); got != wantRecipient {
		t.Errorf("pickIdentityCode(role 2) = %q, want %q — a recipient is still shown a donor's code",
			got, wantRecipient)
	}
}

// TestEnsureIdentityCodeForRoleLeavesSchemelessRolesAlone covers roles 0, 4 and
// 5 (guest, employee, marriage). None has a code column, so the call must be a
// silent no-op rather than an error: moving somebody to employee is an ordinary
// thing to do and must not look like a failure to the role endpoints, which log
// what this returns.
func TestEnsureIdentityCodeForRoleLeavesSchemelessRolesAlone(t *testing.T) {
	pool := newGrantorTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()
	uid := makeUser(t, pool, 1)

	for _, roleID := range []int{0, 4, 5} {
		if err := s.EnsureIdentityCodeForRole(ctx, uid, roleID); err != nil {
			t.Fatalf("EnsureIdentityCodeForRole(role %d) = %v, want nil", roleID, err)
		}
		recipient, volunteer, grantor := codesOf(t, pool, uid)
		if recipient != "" || volunteer != "" || grantor != "" {
			t.Errorf("role %d invented a code: recipient=%q volunteer=%q grantor=%q",
				roleID, recipient, volunteer, grantor)
		}
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
