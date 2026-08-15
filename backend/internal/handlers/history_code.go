// Looking up a history by identity code (K21).
//
// WHAT THIS ADDS
// /api/history built its timeline from the token's own userID and took no code
// parameter, so the client's "search by identity code" had nothing to ask. This
// file adds the authorization rule for asking with a code; the handler in
// extras.go applies it.
//
// ─── THE AUTHORIZATION DECISION, AND WHY IT IS THIS NARROW ─────────────────
//
// An identity code is NOT a secret. It is printed on receipts, written on
// paperwork and quoted in conversation precisely so a person can be referred to
// without using their name. A lookup that accepted any code from any signed-in
// caller would therefore let one user read a stranger's aid history off a slip
// of paper — which is the most sensitive data this project holds, and exactly
// what the codes exist to protect.
//
// So the rule implemented here is the CONSERVATIVE one:
//
//	the owner of the code                         -> allowed
//	staff carrying the (users, view) permission    -> allowed
//	anyone else                                    -> refused, and refused in a
//	  way that does not reveal whether the code exists
//
// Two details carry most of the safety:
//
//   - A signed-in stranger gets the SAME answer as an unknown code. Saying
//     "403, that is someone else's" would confirm the code is real and turn
//     this endpoint into an oracle for enumerating valid codes — which are
//     sequential (ER-000123, GR-000124), so confirming one confirms the range.
//   - A staff caller lacking the permission is refused BEFORE the code is
//     resolved, so their refusal is equally uninformative.
//
// THE PERMISSION CHOSEN, WHICH IS AN ASSUMPTION THE OWNER MAY OVERRIDE:
// (users, view) — the same module and action that already gates /admin/users,
// where the staff identity-code search lives. If the owner decides a narrower
// gate is right (a dedicated module, or admin-level only), the change is the
// two constants below and nothing else.
package handlers

import "github.com/karam-flutter/humanitarian-backend/internal/permissions"

// The (module, action) a staff member must hold to read somebody ELSE'S history
// by code. Named constants rather than inline strings so the policy is one
// edit, in one place, if the owner rules differently.
const (
	historyCodeModule = "users"
	historyCodeAction = permissions.ActionView
)

// historyCodeDecision is the outcome of the rule above.
type historyCodeDecision int

const (
	// historyCodeNotFound covers BOTH "no such code" and "that code is somebody
	// else's, and you are not staff". They are deliberately the same value:
	// telling them apart is what would leak the existence of a code.
	historyCodeNotFound historyCodeDecision = iota
	historyCodeOwner
	historyCodeStaff
	historyCodePermissionDenied
)

// String makes a failing test read as the rule rather than as an integer.
func (d historyCodeDecision) String() string {
	switch d {
	case historyCodeOwner:
		return "owner"
	case historyCodeStaff:
		return "staff"
	case historyCodePermissionDenied:
		return "permission_denied"
	default:
		return "not_found"
	}
}

// decideHistoryCodeAccess applies the rule. It is pure — no database, no
// request — so the policy can be read and tested on its own, which is the point
// of extracting it: this is the decision most worth being sure about in K21.
//
// targetUserID is 0 when the code resolved to nobody.
func decideHistoryCodeAccess(callerUserID, targetUserID int64, isStaff, staffPermitted bool) historyCodeDecision {
	// The owner, always — including a staff member reading their own history,
	// which needs no permission. Guarded on > 0 so an unidentified caller (0)
	// can never "own" an unresolvable code (also 0).
	if targetUserID > 0 && targetUserID == callerUserID {
		return historyCodeOwner
	}
	if !isStaff {
		return historyCodeNotFound
	}
	// Checked before the code is considered, so the refusal says nothing about
	// whether it matches anybody.
	if !staffPermitted {
		return historyCodePermissionDenied
	}
	if targetUserID <= 0 {
		return historyCodeNotFound
	}
	return historyCodeStaff
}
