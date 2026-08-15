// admin_user_guard.go — the shared rank check for every write on the users
// resource (H13).
//
// # WHY THIS FILE EXISTS
//
// The users resource has nine write endpoints spread across three handlers.
// Eight of them asked "is the target protected?" before touching the row; one —
// PATCH /api/admin/users/:id, the only route that can rewrite `users.phone` —
// did not. The check lived as a private method on AdminStatusHandler, so
// AdminEditHandler could not call it even if someone had thought to. This file
// moves that check to one place both handlers reach, and states the rules once.
//
// # WHY THE RULES CHANGED SHAPE
//
// The old check asked a single question: "is the target a super_admin?" That
// was the right question while `users.phone` was only a contact detail. It is
// not only that any more: the phone is where a sign-in code is delivered, so
// whoever holds the number can complete at least one factor of another person's
// sign-in. How far that gets an attacker depends on the auth design, which is
// being revised — do not read a permanent claim about it into this file. What
// is verifiable TODAY, in production, is narrower and enough:
//
//	staff_tier    accounts   with NO password at all
//	super_admin          3                         1
//	admin                2                         1
//
// For those two staff accounts, and for 34 of the 41 ordinary users, there is
// no second factor to fall back on — the phone number is currently sufficient
// on its own. Rewriting one is therefore a credential write, not a contact
// edit, and it belongs behind an authorisation rule regardless of where the
// login design lands.
//
// Two rules follow, and both are enforced here:
//
//	(a) TIER FLOOR — you may not write to an account that outranks you, on any
//	    field. The old super_admin-only check is this same rule with the target
//	    pinned at the top of the ladder; stating it as a floor closes the
//	    identical door one rung down, where a supervisor resets an admin's
//	    password or an employee suspends a supervisor.
//
//	(b) CREDENTIAL RULE — changing the phone of an account that HOLDS DASHBOARD
//	    ACCESS is Super-Admin-only, whoever the actor is. Rule (a) permits a
//	    peer edit, and a peer edit of a sign-in number is still an account
//	    takeover, just a sideways one. The rule deliberately stops at staff:
//	    correcting a beneficiary's mistyped number is an everyday task and stays
//	    available to any rank holding (users, edit).
//
// There is no self-exemption. Changing your OWN sign-in number through this
// route proves nothing about the new handset — no code is ever sent to it — so
// the exemption would be a way to convert borrowed session access (an unlocked
// laptop, a live token) into permanent ownership of the account. The legitimate
// self-service path exists elsewhere and is untouched: POST
// /api/auth/guest/upgrade/verify attaches a phone to the CALLER'S OWN row, and
// only after that number has answered a code (auth.go GuestUpgradeVerify →
// users.UpgradeGuestPhone).
package handlers

import (
	"errors"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// denyUserWrite writes a refusal and records it server-side.
//
// Mirrors auth.denyAuthz, which the middleware layer uses, on the two rules the
// dashboard depends on:
//   - `code` is a STABLE machine key the SPA maps through its `error.*`
//     namespace, so the operator reads the refusal in their own language. The
//     English in `error` is for the logs and non-SPA callers, never the screen.
//   - every refusal is logged. A silent 403 is invisible both to the employee
//     wondering why a button does nothing and to whoever is quietly probing for
//     an account they can take over.
//
// The envelope is `{success:false}` rather than the middleware's
// `{status:"error"}` because that is what every handler on this resource
// already returns and what the SPA's describeError reads.
func denyUserWrite(c *gin.Context, status int, code, message string, targetID int64) {
	actorID := int64(0)
	actorTier := ""
	if u, ok := auth.UserFromGin(c); ok && u != nil {
		actorID, actorTier = u.UserID, u.StaffTier
	}
	log.Printf("[authz] denied %s %s — code=%s actor_id=%d actor_tier=%q target_id=%d ip=%s",
		c.Request.Method, c.Request.URL.Path, code, actorID, actorTier, targetID, c.ClientIP())
	c.JSON(status, gin.H{"success": false, "error": message, "code": code})
}

// guardUserWrite decides whether this caller may write to this user row.
//
// Returns true when the caller must be STOPPED — the refusal has already been
// written, so the handler returns immediately, exactly like the
// blockIfProtectedTarget convention it replaces.
//
// changingPhone tells the guard whether this particular request rewrites the
// sign-in credential; pass false for status/role/password writes, which rule
// (b) does not apply to.
//
// Failure modes are CLOSED. An actor we cannot identify, or a target whose rank
// we cannot read, is refused rather than waved through — the one exception is a
// target row that genuinely does not exist, which falls through so the handler
// can answer its own 404. There is no rank to escalate to on a missing row, and
// turning "no such user" into "forbidden" would only hide typos from staff.
func guardUserWrite(c *gin.Context, pool *pgxpool.Pool, targetID int64, changingPhone bool) bool {
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		denyUserWrite(c, http.StatusUnauthorized, "auth_required", "Not authenticated.", targetID)
		return true
	}

	var rawTier *string
	err := pool.QueryRow(c.Request.Context(),
		"SELECT staff_tier FROM users WHERE id = $1", targetID).Scan(&rawTier)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return false // no such user — let the handler surface its own 404.
	case err != nil:
		// We do not know who we are about to modify. Refuse.
		log.Printf("[authz] target tier lookup failed on %s %s — target_id=%d: %v",
			c.Request.Method, c.Request.URL.Path, targetID, err)
		denyUserWrite(c, http.StatusInternalServerError, "server_error",
			"Could not verify this account. Please try again.", targetID)
		return true
	}

	targetTier := permissions.TierUser
	if rawTier != nil {
		targetTier = permissions.TierFrom(*rawTier)
	}
	actorTier := permissions.TierFrom(actor.StaffTier)

	// (a) Tier floor — never write upwards.
	if tierRank(string(targetTier)) > tierRank(string(actorTier)) {
		denyUserWrite(c, http.StatusForbidden, "protected_account",
			"This account holds a higher access level than yours and cannot be modified from here.",
			targetID)
		return true
	}

	// (b) Credential rule — a staff sign-in number is the Super-Admin's to move.
	if changingPhone && targetTier != permissions.TierUser && actorTier != permissions.TierSuperAdmin {
		denyUserWrite(c, http.StatusForbidden, "staff_phone_super_admin_only",
			"Only a Super-Admin can change the sign-in number of a staff account.",
			targetID)
		return true
	}

	return false
}
