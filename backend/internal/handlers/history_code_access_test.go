// K21 — WHOSE history an identity code may reveal.
//
// THE DECISION THIS PINS
// An identity code is printed on a receipt and quoted in conversation. It is an
// identifier, not a secret, so a lookup that accepts any code from any
// signed-in caller would let one user read a stranger's aid history from a slip
// of paper — the single most sensitive data this project holds.
//
// The rule implemented here is the CONSERVATIVE one, and it is a default the
// owner may widen, not a law:
//
//	the owner of the code                                  -> allowed
//	staff carrying the (users, view) permission             -> allowed
//	anybody else                                            -> 404, worded and
//	  shaped exactly like an unknown code
//
// The last line is the part that is easy to get wrong. Answering "403, that is
// someone else's" would confirm that a code EXISTS, which turns the endpoint
// into an oracle for enumerating valid codes. A staff caller who lacks the
// permission is refused BEFORE the code is resolved, so the refusal says
// nothing about whether it matches anyone either.
//
// These are pure decision tests: no database, no HTTP, always run.
package handlers

import "testing"

func TestDecideHistoryCodeAccess(t *testing.T) {
	const caller int64 = 7

	tests := []struct {
		name           string
		target         int64
		isStaff        bool
		staffPermitted bool
		want           historyCodeDecision
	}{
		{
			name:   "the owner of the code reads their own history",
			target: caller,
			want:   historyCodeOwner,
		},
		{
			// The whole point of K21 for a normal user: their own receipt.
			name:           "the owner is allowed without any staff permission",
			target:         caller,
			isStaff:        true,
			staffPermitted: false,
			want:           historyCodeOwner,
		},
		{
			// The refusal that matters. Same answer as an unknown code, so the
			// endpoint cannot be used to discover which codes are real.
			name:   "a signed-in stranger is refused as if the code did not exist",
			target: 9,
			want:   historyCodeNotFound,
		},
		{
			name:   "an unknown code is refused for a normal user",
			target: 0,
			want:   historyCodeNotFound,
		},
		{
			name:           "staff with the permission may read another person's history",
			target:         9,
			isStaff:        true,
			staffPermitted: true,
			want:           historyCodeStaff,
		},
		{
			name:           "staff without the permission are told so, not given the data",
			target:         9,
			isStaff:        true,
			staffPermitted: false,
			want:           historyCodePermissionDenied,
		},
		{
			// Refused on the permission BEFORE the code is considered, so the
			// answer reveals nothing about whether it matches anyone.
			name:           "staff without the permission cannot probe for unknown codes",
			target:         0,
			isStaff:        true,
			staffPermitted: false,
			want:           historyCodePermissionDenied,
		},
		{
			name:           "staff with the permission still get nothing for an unknown code",
			target:         0,
			isStaff:        true,
			staffPermitted: true,
			want:           historyCodeNotFound,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := decideHistoryCodeAccess(caller, tc.target, tc.isStaff, tc.staffPermitted)
			if got != tc.want {
				t.Errorf("decideHistoryCodeAccess(caller=%d, target=%d, staff=%v, permitted=%v) = %v, want %v",
					caller, tc.target, tc.isStaff, tc.staffPermitted, got, tc.want)
			}
		})
	}
}

// TestDecideHistoryCodeAccessNeverMatchesAnAnonymousCaller guards the edge that
// would silently open the endpoint: a caller id of 0 is "nobody", and it must
// never be treated as owning an unresolvable code just because both are zero.
func TestDecideHistoryCodeAccessNeverMatchesAnAnonymousCaller(t *testing.T) {
	if got := decideHistoryCodeAccess(0, 0, false, false); got != historyCodeNotFound {
		t.Errorf("an unidentified caller was granted %v for an unknown code; want historyCodeNotFound", got)
	}
}
