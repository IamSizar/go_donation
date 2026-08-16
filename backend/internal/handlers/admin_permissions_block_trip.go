// admin_permissions_block_trip.go — the two paths that WRITE to a section
// block: tripping one, and lifting it (H14).
//
// Split out of admin_permissions_block.go, which holds the reading side (is this
// actor frozen, and how many changes have they made). The two halves are
// genuinely different jobs: everything here mutates state and has to be careful
// about clocks, cancellation and what it claims to have sent, while the reading
// side is a lookup on the request path that must stay cheap and must fail open.
//
// Read the header of admin_permissions_block.go first — it carries the design
// decisions both files answer to, in particular the definition of "rapid", the
// one-clock rule, and the promise that nothing here reports a message that did
// not leave the server.
package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// tripBlockIfBursting is called AFTER a permission change has been applied and
// audited. It counts, and if the actor has crossed the line it freezes the
// section, ends their sessions, and tries to send the unlock code.
//
// It runs on a FRESH background context rather than the request's. The party
// this acts against is the party holding the request, and a caller who
// disconnects the moment their write lands must not be able to cancel the
// security response to it. Bounded by permBlockRecordTimeout so a wedged gateway
// cannot hold the handler open indefinitely.
//
// Deliberately best-effort in the same way every other force-logout call site
// in this package is: the change that triggered it is already written and
// audited, so a failure here is logged rather than turned into an error the
// operator cannot act on. The one thing it will never do is report a message it
// did not send.
func (h *AdminPermissionsHandler) tripBlockIfBursting(c *gin.Context, actorID int64, phone string) {
	max := permBurstMax()
	if max <= 0 {
		return // disabled by configuration
	}
	ctx, cancel := context.WithTimeout(context.Background(), permBlockRecordTimeout)
	defer cancel()

	window := permBurstWindow()
	count := h.recentChangeCount(ctx, actorID, window)
	if count < 0 || count <= max {
		return
	}

	// ── Send the code FIRST, so the freeze length can depend on whether one
	// actually left the server. ──
	delivery := h.sendUnlockCode(ctx, actorID, phone)
	duration := permBlockDuration(delivery.Delivered())

	// The hash is the only form of the code this process keeps. If hashing fails
	// the block still happens — with no code, and therefore on the short
	// cooldown, because a freeze whose only exit is a code nobody can verify is
	// the lockout this file exists to avoid.
	var hashArg, channelArg any
	if delivery.Delivered() {
		hash, err := bcrypt.GenerateFromPassword([]byte(delivery.Code), bcrypt.DefaultCost)
		if err != nil {
			log.Printf("[security] H14: could not hash the unlock code for actor %d: %v", actorID, err)
			duration = permBlockDuration(false)
		} else {
			hashArg, channelArg = string(hash), delivery.Channel
		}
	}

	// ── Freeze, then end the sessions. In that order: a logout without a
	// recorded freeze would be an unexplained sign-out the operator could simply
	// undo by logging back in. ──
	//
	// Every timestamp comes from LOCALTIMESTAMP, the same clock
	// permission_audit_log.created_at is stamped from. unlock_sent_at is set only
	// when something was actually sent, so a NULL there and a NULL in
	// unlock_channel always agree.
	if _, err := h.Perms.Pool.Exec(ctx,
		`INSERT INTO permission_section_blocks
		   (actor_user_id, blocked_at, expires_at, trigger_count, window_seconds,
		    unlock_code_hash, unlock_sent_at, unlock_channel, unlock_attempts, lifted_at)
		 VALUES ($1, LOCALTIMESTAMP, LOCALTIMESTAMP + make_interval(secs => $2), $3, $4,
		         $5, CASE WHEN $6::text IS NULL THEN NULL ELSE LOCALTIMESTAMP END, $6, 0, NULL)
		 ON CONFLICT (actor_user_id) DO UPDATE
		   SET blocked_at = EXCLUDED.blocked_at, expires_at = EXCLUDED.expires_at,
		       trigger_count = EXCLUDED.trigger_count,
		       window_seconds = EXCLUDED.window_seconds,
		       unlock_code_hash = EXCLUDED.unlock_code_hash,
		       unlock_sent_at = EXCLUDED.unlock_sent_at,
		       unlock_channel = EXCLUDED.unlock_channel,
		       unlock_attempts = 0, lifted_at = NULL`,
		actorID, duration.Seconds(), count, int(window.Seconds()),
		hashArg, channelArg); err != nil {
		log.Printf("[security] H14: could not record the block for actor %d: %v", actorID, err)
		return
	}

	ended := int64(0)
	if n, err := revokeSessionsForUser(ctx, h.Perms.Pool, actorID); err != nil {
		log.Printf("[security] H14: force-logout failed for blocked actor %d: %v", actorID, err)
	} else {
		ended = n
		_, _ = h.Perms.Pool.Exec(ctx,
			`UPDATE permission_section_blocks SET sessions_ended = $1 WHERE actor_user_id = $2`,
			ended, actorID)
	}

	// The channel string is the operator-visible record of how the block will
	// end, and it never claims a message that was not sent.
	how := "nothing_sent"
	if delivery.Delivered() {
		how = delivery.Channel + " to " + delivery.Hint
	}
	log.Printf("[security] H14: actor %d BLOCKED from the permissions section — %d changes in %s "+
		"(limit %d); %d session(s) ended; unlock=%s; lapses in %s",
		actorID, count, window, max, ended, how, duration)

	id := actorID
	_ = h.Perms.LogAudit(ctx, &id, permBlockAuditAction,
		"actor#"+strconv.FormatInt(actorID, 10),
		strconv.Itoa(count)+" changes/"+window.String(),
		"blocked for "+duration.String()+" (unlock="+unlockWord(delivery)+")",
		c.ClientIP())
}

// unlockWord names the exit route for the audit trail. Kept separate from the
// log line above because the audit ledger is hash-chained and read by operators
// months later: it gets the channel, never the masked destination, so no part of
// a phone number or an address is copied into an immutable row.
func unlockWord(d unlockDelivery) string {
	if !d.Delivered() {
		return "none_sent"
	}
	return d.Channel
}

// ─── Lifting the block ──────────────────────────────────────────────────

type permUnlockReq struct {
	Code string `json:"code"`
}

// POST /api/admin/permissions/unlock — lift the freeze with the code that was
// sent.
//
// Reachable while blocked ON PURPOSE: the block freezes permission WRITES, not
// the dashboard, so the actor signs in again (the burst ended their session)
// and lifts the section from here. If they were locked out of sign-in too there
// would be nowhere to type the code.
func (h *AdminPermissionsHandler) Unlock(c *gin.Context) {
	actor, ok := auth.UserFromGin(c)
	if !ok || actor == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "code": "auth_required", "error": "Not authenticated."})
		return
	}
	ctx := c.Request.Context()

	var req permUnlockReq
	_ = c.ShouldBindJSON(&req)
	code := strings.TrimSpace(req.Code)

	// Liveness and the remaining seconds both come from the database's clock, in
	// one round trip, for the same reason as blockedFromSection.
	var hash, channel *string
	var attempts, retryAfter int
	err := h.Perms.Pool.QueryRow(ctx,
		`SELECT unlock_code_hash, unlock_channel, unlock_attempts,
		        GREATEST(1, CEIL(EXTRACT(EPOCH FROM (expires_at - LOCALTIMESTAMP))))::int
		   FROM permission_section_blocks
		  WHERE actor_user_id = $1
		    AND lifted_at IS NULL
		    AND expires_at > LOCALTIMESTAMP`, actor.UserID,
	).Scan(&hash, &channel, &attempts, &retryAfter)
	if errors.Is(err, pgx.ErrNoRows) {
		// Nothing to lift. Reported as success: the caller's goal — "let me back
		// into this section" — is already true, and a 404 here would just send an
		// operator hunting for a block that is not there.
		c.JSON(http.StatusOK, gin.H{"success": true, "blocked": false})
		return
	}
	if err != nil {
		log.Printf("[security] H14: unlock lookup failed for actor %d: %v", actor.UserID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "code": "server_error",
			"error": "Could not check the lock. Please try again."})
		return
	}

	if hash == nil || *hash == "" {
		// No code was ever sent, so there is nothing to type. Say when the lock
		// ends instead of inviting a guess at a code that does not exist.
		c.JSON(statusPermSectionLocked, gin.H{
			"success": false, "code": "perm_section_blocked_wait",
			"error": "No unlock code was sent, because neither SMS nor email delivery is " +
				"configured on the server. The lock clears by itself.",
			"retry_after": retryAfter, "unlock_channel": "", "unlock_by_sms": false,
		})
		return
	}
	if attempts >= permUnlockMaxAttempts {
		c.JSON(statusPermSectionLocked, gin.H{
			"success": false, "code": "perm_unlock_attempts",
			"error":       "Too many incorrect unlock codes. The lock now has to run its course.",
			"retry_after": retryAfter, "unlock_channel": "", "unlock_by_sms": false,
		})
		return
	}
	if !auth.ValidateCodeFormat(code) || bcrypt.CompareHashAndPassword([]byte(*hash), []byte(code)) != nil {
		if _, err := h.Perms.Pool.Exec(ctx,
			`UPDATE permission_section_blocks SET unlock_attempts = unlock_attempts + 1
			  WHERE actor_user_id = $1`, actor.UserID); err != nil {
			log.Printf("[security] H14: could not record a failed unlock for actor %d: %v", actor.UserID, err)
		}
		log.Printf("[security] H14: wrong unlock code from actor %d at %s", actor.UserID, c.ClientIP())
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "code": "perm_unlock_invalid",
			"error": "Incorrect unlock code."})
		return
	}

	if _, err := h.Perms.Pool.Exec(ctx,
		`UPDATE permission_section_blocks SET lifted_at = LOCALTIMESTAMP WHERE actor_user_id = $1`,
		actor.UserID); err != nil {
		log.Printf("[security] H14: could not lift the block for actor %d: %v", actor.UserID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "code": "server_error",
			"error": "Could not lift the lock. Please try again."})
		return
	}
	// blocked_at is deliberately LEFT WHERE IT IS. It is the floor the burst
	// counter starts from (see recentChangeCount), so the changes that tripped
	// this block cannot go on to trip the next one — which is what stops the
	// section re-freezing on the operator's very next click.
	via := permBlockChannelNone
	if channel != nil {
		via = *channel
	}
	log.Printf("[security] H14: actor %d lifted their permissions-section block with the %s code",
		actor.UserID, via)
	id := actor.UserID
	_ = h.Perms.LogAudit(ctx, &id, permUnlockAuditAction,
		"actor#"+strconv.FormatInt(actor.UserID, 10), "blocked", "unblocked by "+via+" code", c.ClientIP())
	c.JSON(http.StatusOK, gin.H{"success": true, "blocked": false})
}
