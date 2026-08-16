// admin_permissions_block.go — the burst block on إدارة الصلاحيات (H14).
//
// # WHAT THE CLIENT ASKED FOR
//
// "حظر مؤقت وتسجيل خروج تلقائي فوري مع رسالة تأكيد SMS لرفع الحظر، عند اكتشاف
// عمليات تعديل/حذف متكررة وسريعة في هذا القسم" — a temporary block plus an
// immediate automatic logout, lifted by an SMS confirmation, when repeated and
// rapid change/delete operations are detected in this section.
//
// # WHAT "RAPID" MEANS HERE, STATED SO IT CAN BE ARGUED WITH
//
//	MORE THAN 12 PERMISSION CHANGES BY ONE ACTOR WITHIN 60 SECONDS.
//
// The number is chosen against what the screen actually costs a human. Every
// change on it needs a password prompt AND a single-use code prompt (H1), so a
// person working quickly manages a handful a minute; 12 is comfortably above
// anything a human does and far below what a script does in its first second.
// Both halves are configurable — PERM_BURST_MAX and PERM_BURST_WINDOW_SECONDS —
// and setting PERM_BURST_MAX to 0 disables the whole mechanism.
//
// Unlike the older in-memory throttle beside it, this is ON BY DEFAULT. The
// throttle could be left off safely because all it did was answer 429 for a
// minute; this one is the thing the client asked for, and a protection that
// ships switched off is not a protection.
//
// # WHY THE COUNT COMES FROM THE AUDIT LOG
//
// permission_audit_log already records every permission change with actor_id
// and created_at, is immutable, and is shared across replicas. Counting from it
// means the detector cannot fall out of step with the writes it is detecting —
// which is precisely what went wrong with the in-memory limiter, which knows
// only about the paths that remembered to call it. It also means a burst spread
// across two server replicas is still one burst.
//
// Two things follow that are easy to get wrong, and both were wrong in the first
// draft of this file:
//
//   - The count is filtered to the three actions that ARE permission changes.
//     Tripping the block appends its own row to permission_audit_log under the
//     same actor, and so does lifting it, so an unfiltered count is a detector
//     reading its own output as evidence.
//   - The count starts again at each trip. The window is a sliding one, so the
//     instant a block is lifted every change from the burst is still inside it;
//     without the reset the next click re-freezes the section and sends a second
//     code. An unlock that buys one action is not an unlock.
//
// # ONE DATABASE, ONE CLOCK
//
// Every timestamp on permission_section_blocks is written and compared with
// LOCALTIMESTAMP, never from Go. permission_audit_log.created_at is stamped by
// Postgres (CURRENT_TIMESTAMP into a naive column, i.e. the database's local
// wall clock), and the deployment timezone is Asia/Baghdad. A block that took
// its timestamps from Go in UTC — as the first draft did — landed three hours
// away from the audit row written a millisecond beside it, which made every
// cross-table comparison wrong and made expires_at read as already past to
// anyone querying the table. The bug is invisible on a UTC machine, which is
// exactly why it is pinned by a test.
//
// # WHAT THE BLOCK ACTUALLY BLOCKS, AND WHAT IT DELIBERATELY DOES NOT
//
// It freezes THE SECTION: further permission writes by that actor are refused
// with 423 Locked. It does NOT block sign-in, and it does not touch the rest of
// the dashboard.
//
// That narrowing is the whole design, not a shortcut. Blocking sign-in would,
// on a server with no gateway configured — which is every server today — leave
// the only super_admin permanently outside their own dashboard with no way back
// in. The threat the client described is a session hammering the permission
// matrix, and ending that session (which this does) plus freezing the section
// (which this does) stops it. Bricking the platform is not part of stopping it.
//
// # DEGRADING HONESTLY WHEN NOTHING CAN BE SENT
//
// OTPIQ_API_KEY and SMTP_* are empty in every environment the team can reach.
// The rule this file follows:
//
//	THE BLOCK MUST NEVER OUTLIVE THE ONLY CHANNEL THAT CAN LIFT IT.
//
// With a real channel a code is sent and the block runs for PERM_BLOCK_HOURS
// (default 1) with the code as the way out. With no channel, NO CODE IS INVENTED
// and no code is echoed back — the block instead lapses on its own after
// PERM_BLOCK_COOLDOWN_MINUTES (default 15), and both the refusal and the log say
// plainly that nothing was sent and when the freeze ends. There is no path here
// that reports a message that did not leave the server.
package handlers

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

// Defaults for the knobs. Every one of them is deliberately a number a reviewer
// can disagree with in one line rather than a constant buried in a condition.
const (
	permBurstMaxDefault    = 12               // changes…
	permBurstWindowDefault = 60 * time.Second // …within this window trips the block

	// permBlockDeliveredDefault is how long the freeze runs when a code was
	// actually delivered. One hour, not the day the first draft chose.
	//
	// The long tail buys almost nothing: the legitimate owner lifts the freeze
	// the moment they read the code, and an attacker holding the session but not
	// the phone or the inbox is stopped by the code rather than by the clock. All
	// of the freeze's real work — ending the live sessions, forcing a fresh
	// sign-in, demanding an out-of-band acknowledgement — is done in its first
	// seconds. What a long default DOES buy is the risk of stranding the owner
	// for a day after five mistyped codes, and stranding them is the failure this
	// whole row is written to avoid. Raise PERM_BLOCK_HOURS for a harsher policy.
	permBlockDeliveredDefault = 1 * time.Hour
	// permBlockNoChannelDefault is how long it runs when nothing could be sent,
	// and it is short because lapsing is then the ONLY way out.
	permBlockNoChannelDefault = 15 * time.Minute

	permUnlockMaxAttempts   = 5 // guesses at the unlock code
	permBlockAuditAction    = "permission_section_blocked"
	permUnlockAuditAction   = "permission_section_unblocked"
	statusPermSectionLocked = http.StatusLocked // 423

	// permBlockRecordTimeout bounds the work done AFTER a burst is detected —
	// sending the code, hashing it, writing the row, ending the sessions. See
	// tripBlockIfBursting on why that work does not run on the request context.
	permBlockRecordTimeout = 30 * time.Second
)

// permChangeActions are the audit actions that ARE permission changes, and so
// the only ones the burst counter may count. Everything else in
// permission_audit_log under this actor — including the block's own bookkeeping
// — is the feature talking about itself.
var permChangeActions = []string{"permission_set", "user_permission_set", "user_permission_cleared"}

// permBurstMax is the number of changes that trips the block; 0 disables it.
func permBurstMax() int { return envInt("PERM_BURST_MAX", permBurstMaxDefault, 0, 10000) }

// permBurstWindow is the sliding window the changes are counted in.
func permBurstWindow() time.Duration {
	return time.Duration(envInt("PERM_BURST_WINDOW_SECONDS",
		int(permBurstWindowDefault.Seconds()), 5, 3600)) * time.Second
}

// permBlockDuration returns how long a freeze lasts, given whether an unlock
// code could actually be delivered. See the file header: the block must never
// outlive the channel that lifts it.
func permBlockDuration(delivered bool) time.Duration {
	if delivered {
		return time.Duration(envInt("PERM_BLOCK_HOURS",
			int(permBlockDeliveredDefault.Hours()), 1, 720)) * time.Hour
	}
	return time.Duration(envInt("PERM_BLOCK_COOLDOWN_MINUTES",
		int(permBlockNoChannelDefault.Minutes()), 1, 1440)) * time.Minute
}

// envInt reads an int from the environment, clamped to [min,max], falling back
// to def when unset or unparseable. Mirrors config.parseIntDefault, restated
// here because internal/handlers reads no configuration package.
func envInt(key string, def, min, max int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	if n < min {
		return min
	}
	if n > max {
		return max
	}
	return n
}

// permSectionBlock is a live freeze on one actor.
type permSectionBlock struct {
	Channel    string // permBlockChannel* — "" when nothing was delivered
	Attempts   int
	RetryAfter int // seconds until it lapses on its own, per the database's clock
}

// HasCode reports whether there is a code to type at all.
func (b permSectionBlock) HasCode() bool { return b.Channel != permBlockChannelNone }

// ─── Reading the block ──────────────────────────────────────────────────

// blockedFromSection returns the live block for an actor, or nil.
//
// Liveness is decided in SQL (`lifted_at IS NULL AND expires_at > LOCALTIMESTAMP`)
// rather than by scanning the row into Go and comparing there, so the question
// "is this block still running" is answered by the same clock that wrote it. See
// the file header.
//
// Fails OPEN on a database error, matching LoginLockStore.Status and for the
// same reason: a bug in the freeze must never be able to wedge every
// Super-Admin out of the permissions screen. A detector that can only ever
// under-block is the right failure direction for a mechanism whose worst case
// is a lockout.
func (h *AdminPermissionsHandler) blockedFromSection(ctx context.Context, actorID int64) *permSectionBlock {
	var channel *string
	var attempts, retryAfter int
	err := h.Perms.Pool.QueryRow(ctx,
		`SELECT unlock_channel, unlock_attempts,
		        GREATEST(1, CEIL(EXTRACT(EPOCH FROM (expires_at - LOCALTIMESTAMP))))::int
		   FROM permission_section_blocks
		  WHERE actor_user_id = $1
		    AND lifted_at IS NULL
		    AND expires_at > LOCALTIMESTAMP`, actorID,
	).Scan(&channel, &attempts, &retryAfter)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			log.Printf("[security] H14: block lookup failed for actor %d (failing open): %v", actorID, err)
		}
		return nil // no row, lifted, lapsed — or unreadable, which fails open
	}
	blk := &permSectionBlock{Attempts: attempts, RetryAfter: retryAfter}
	if channel != nil {
		blk.Channel = *channel
	}
	return blk
}

// refuseBlocked writes the 423 and reports true, so a handler reads as
//
//	if h.refuseBlocked(c, actor.UserID) { return }
//
// The body distinguishes the cases the operator has to act on differently: with
// a code they go and read it — on the phone or in the inbox, and the response
// says which — and without one they wait, and are told until when.
func (h *AdminPermissionsHandler) refuseBlocked(c *gin.Context, actorID int64) bool {
	blk := h.blockedFromSection(c.Request.Context(), actorID)
	if blk == nil {
		return false
	}
	const preamble = "This section is temporarily locked after a rapid burst of permission changes. "
	code := "perm_section_blocked_wait"
	message := preamble + "No unlock code could be sent, because neither SMS nor email delivery " +
		"is configured on the server, so the lock clears by itself shortly."
	switch blk.Channel {
	case permBlockChannelSMS:
		code = "perm_section_blocked_sms"
		message = preamble + "Enter the unlock code sent to your phone to continue."
	case permBlockChannelEmail:
		code = "perm_section_blocked_email"
		message = preamble + "Enter the unlock code sent to your email to continue."
	}
	c.JSON(statusPermSectionLocked, gin.H{
		"success": false, "code": code, "error": message,
		"retry_after":    blk.RetryAfter,
		"unlock_channel": blk.Channel, // "" when nothing was delivered
		// Kept under its original name because a test and the first draft of the
		// dashboard both read it. It means strictly "a code went by SMS".
		"unlock_by_sms": blk.Channel == permBlockChannelSMS,
	})
	return true
}

// ─── Tripping the block ─────────────────────────────────────────────────

// recentChangeCount asks the immutable audit trail how many permission changes
// this actor has made inside the window. Returns -1 when it cannot tell, which
// callers treat as "do not trip" — see blockedFromSection on failing open.
//
// The floor is the LATER of "the window started" and "this actor was last
// blocked", which is what makes an unlock mean something: the changes that were
// already spent tripping the previous block do not get to trip the next one too.
// COALESCE to -infinity covers the ordinary case of an actor who has never been
// blocked, for whom the window alone decides.
func (h *AdminPermissionsHandler) recentChangeCount(
	ctx context.Context, actorID int64, window time.Duration,
) int {
	var n int
	if err := h.Perms.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM permission_audit_log
		  WHERE actor_id = $1
		    AND action = ANY($3::text[])
		    AND created_at > GREATEST(
		          LOCALTIMESTAMP - make_interval(secs => $2),
		          COALESCE((SELECT blocked_at FROM permission_section_blocks
		                     WHERE actor_user_id = $1), '-infinity'::timestamp))`,
		actorID, window.Seconds(), permChangeActions,
	).Scan(&n); err != nil {
		log.Printf("[security] H14: burst count failed for actor %d: %v", actorID, err)
		return -1
	}
	return n
}
