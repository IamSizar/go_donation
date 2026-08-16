// admin_permissions_block_test.go — does a burst of permission changes actually
// stop, and can it be lifted (H14)?
//
// # WHAT WAS THERE BEFORE
//
// One in-memory 429 counter, disabled unless PERM_CHANGE_MAX_PER_MIN happened
// to be set. Nothing blocked the account, nothing signed it out, and nothing had
// to be answered out of band to carry on. The client asked for all three.
//
// # WHAT THESE PIN
//
//   - A burst FREEZES the section: the next change is refused 423 and is not
//     applied. This is the case that fails on the parent commit.
//   - The burst ENDS THE ACTOR'S SESSIONS, which is the "تسجيل خروج تلقائي
//     فوري" half and the only part that stops a session already in flight.
//   - Ordinary work is untouched: a handful of changes trips nothing.
//   - With a real gateway — SMS, or email when that is the only one configured —
//     the unlock code lifts the freeze and a wrong code does not, and the actor
//     can go straight back to work rather than re-tripping on the burst they
//     were just released from.
//   - With NO gateway — every environment today — no code is invented, no code
//     is echoed back, and the freeze is SHORT so it lapses on its own. This is
//     the degradation rule: the block must never outlive the only channel that
//     can lift it, or the owner is locked out of the screen that fixes
//     everything else.
//   - The detector counts permission changes, not the rows it writes about
//     itself, and it does its arithmetic on the database's clock rather than
//     Go's — a distinction worth nothing at UTC and worth three hours in
//     Asia/Baghdad, which is where this runs.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_h14
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h14?sslmode=disable' \
//	  go test ./internal/handlers/ -run PermissionBurst -v
package handlers

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ─── Harness ────────────────────────────────────────────────────────────

// newBurstRouter wires the three routes a burst touches, exactly as main.go
// does. `unlock` sits outside the freeze deliberately — see the handler.
//
// Both gateways are arguments because the whole point of this row is what
// happens on each of the three deployments that exist: SMS, email, and the one
// the owner actually runs today, which has neither.
func newBurstRouter(pool *pgxpool.Pool, otpiq *auth.OTPIQClient, mailer *auth.Mailer) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	h := NewAdminPermissionsHandler(permissions.New(pool), auth.NewOTPStore(pool), otpiq, mailer)
	r := gin.New()
	r.POST("/api/admin/permissions",
		auth.RequireAdmin(tokens), auth.RequireSuperAdmin(), h.SetPermission)
	r.POST("/api/admin/permissions/unlock",
		auth.RequireAdmin(tokens), auth.RequireSuperAdmin(), h.Unlock)
	return r
}

// clearBurstState wipes what a burst leaves behind, before the case and again
// after it. Three tables, and the third one is not optional.
//
//   - permission_section_blocks: the block row for this actor.
//   - permission_audit_log: the rows the burst counter reads. Without this the
//     cases contaminate each other, because the counter is deliberately the
//     shared audit trail rather than a per-test counter.
//   - role_permissions: THE OVERRIDES THE BURST ACTUALLY WROTE. A burst is a
//     sequence of real permission changes driven through the real handler, so it
//     leaves real tier-wide DENY rows behind — including supervisor/users/view,
//     which is what a supervisor needs to see the users list at all. Leaving
//     them turns this file into a landmine for every other case that shares the
//     database: TestContactRedactionOnUsersList fails with a 403 that looks
//     exactly like a regression in ITS feature and costs an afternoon to trace
//     back to here. Cleaning up after a test is part of the test.
func clearBurstState(t *testing.T, pool *pgxpool.Pool, actorID int64) {
	t.Helper()
	wipe := func(ctx context.Context) error {
		if _, err := pool.Exec(ctx,
			`DELETE FROM permission_section_blocks WHERE actor_user_id = $1`, actorID); err != nil {
			return err
		}
		if _, err := pool.Exec(ctx,
			`DELETE FROM permission_audit_log WHERE actor_id = $1`, actorID); err != nil {
			return err
		}
		// Scoped to exactly what a burst can write: the supervisor tier's `view`
		// cell for the modules in burstModules, tier-wide (user_id IS NULL). Never
		// a blanket DELETE — this database is shared with every other case in the
		// package, and a test that clears a table it does not own is a worse
		// version of the problem it is fixing.
		_, err := pool.Exec(ctx,
			`DELETE FROM role_permissions
			  WHERE tier = 'supervisor' AND action = 'view'
			    AND user_id IS NULL AND module = ANY($1::text[])`, burstModules)
		return err
	}
	if err := wipe(context.Background()); err != nil {
		t.Fatalf("clear burst state: %v", err)
	}
	t.Cleanup(func() {
		if err := wipe(context.Background()); err != nil {
			t.Errorf("clear burst state after the case: %v", err)
		}
	})
}

// changeAs drives one permission write with both factors genuinely supplied.
func changeAs(
	t *testing.T, pool *pgxpool.Pool, r *gin.Engine, actor authTestAccount,
	password, module string, allowed bool,
) (int, map[string]any) {
	t.Helper()
	code := mintFactor(t, pool, actor.phone)
	return postFactorAs(t, pool, r, "/api/admin/permissions", actor.id, map[string]any{
		"tier": "supervisor", "module": module, "action": "view",
		"allowed": allowed, "otp": code, "password": password,
	})
}

// burstModules gives each write in a burst a distinct target, so the run is a
// sequence of real changes rather than the same row rewritten.
var burstModules = []string{
	"users", "donations", "reports", "marketplace", "beneficiary", "volunteers",
	"partners", "media", "community", "marriage", "sponsorships", "in_kind",
	"support", "tasks", "campaigns",
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestPermissionBurstFreezesTheSection is the client's rule. It sets a small
// threshold through the environment so the case stays fast and readable; the
// mechanism under test is identical at the shipped default of 12.
func TestPermissionBurstFreezesTheSection(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("PERM_BURST_MAX", "3")
	t.Setenv("PERM_BURST_WINDOW_SECONDS", "60")

	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	clearBurstState(t, pool, actor.id)
	r := newBurstRouter(pool, nil, nil) // no gateway at all — production today

	// Under the threshold: ordinary work, nothing frozen.
	for i := 0; i < 3; i++ {
		if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[i], false); status != http.StatusOK {
			t.Fatalf("change %d: status = %d, want 200 (body: %v)", i+1, status, body)
		}
	}
	if blk := (&AdminPermissionsHandler{Perms: permissions.New(pool)}).
		blockedFromSection(context.Background(), actor.id); blk != nil {
		t.Fatalf("the section froze at the threshold — ordinary work must not trip it")
	}

	openSession(t, pool, actor.id)
	if got := liveSessionCount(t, pool, actor.id); got == 0 {
		t.Fatal("precondition: the actor should hold at least one live session")
	}

	// The one that crosses the line still applies (it was already audited when
	// the count was taken), and trips the freeze behind it.
	if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[3], false); status != http.StatusOK {
		t.Fatalf("the tripping change: status = %d, want 200 (body: %v)", status, body)
	}
	if got := liveSessionCount(t, pool, actor.id); got != 0 {
		t.Errorf("the actor still holds %d live session(s) after a burst — "+
			"the automatic logout did not happen", got)
	}

	// The NEXT change must be refused, and must not be applied. Seeded to TRUE
	// first so "still true afterwards" is proof the write did not happen — the
	// built-in default for this cell is already false, so asserting on false
	// alone would pass even if the refusal had written it.
	grantTier(t, pool, "supervisor", burstModules[4], "view", true)
	status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[4], false)
	if status != statusPermSectionLocked {
		t.Fatalf("status = %d, want 423 — the section did not freeze after a burst (body: %v)",
			status, body)
	}
	if got, _ := body["code"].(string); got != "perm_section_blocked_wait" {
		t.Errorf("code = %q, want perm_section_blocked_wait (body: %v)", got, body)
	}
	if allowed, err := permissions.New(pool).Allowed(context.Background(),
		permissions.TierSupervisor, burstModules[4], "view"); err != nil || !allowed {
		t.Errorf("the refused change was applied anyway (allowed=%v, err=%v)", allowed, err)
	}
}

// TestPermissionBurstWithoutSMSLapsesQuickly is the degradation rule, and the
// reason the owner does not get stranded: with no gateway there is no code to
// invent, so the freeze has to be short enough to be survivable and must say so
// rather than inviting a guess.
func TestPermissionBurstWithoutSMSLapsesQuickly(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("PERM_BURST_MAX", "2")
	t.Setenv("PERM_BURST_WINDOW_SECONDS", "60")
	t.Setenv("PERM_BLOCK_COOLDOWN_MINUTES", "15")
	t.Setenv("PERM_BLOCK_HOURS", "24")

	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	clearBurstState(t, pool, actor.id)
	r := newBurstRouter(pool, nil, nil) // no gateway at all

	for i := 0; i < 3; i++ {
		if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[i], false); status != http.StatusOK {
			t.Fatalf("change %d: status = %d (body: %v)", i+1, status, body)
		}
	}

	var hash, channel *string
	var secondsLeft float64
	// Measured IN SQL, against the database's own clock, because that is the
	// clock the block is written and compared on. Scanning expires_at into Go and
	// subtracting time.Now() is the naive cross-clock comparison this row had to
	// remove from the handler — see TestPermissionBlockSharesTheDatabaseClock —
	// and doing it here would only re-introduce it in the test.
	if err := pool.QueryRow(context.Background(),
		`SELECT unlock_code_hash, unlock_channel,
		        EXTRACT(EPOCH FROM (expires_at - LOCALTIMESTAMP))
		   FROM permission_section_blocks WHERE actor_user_id = $1`, actor.id,
	).Scan(&hash, &channel, &secondsLeft); err != nil {
		t.Fatalf("read the block: %v", err)
	}
	if hash != nil || channel != nil {
		t.Errorf("an unlock code was recorded with no gateway configured "+
			"(hash=%v channel=%v) — a code nobody could receive is worse than none", hash, channel)
	}
	// Short, because lapsing is the ONLY way out.
	if secondsLeft > time.Hour.Seconds() {
		t.Errorf("the freeze runs for %.0fs with no channel to lift it — "+
			"that is a lockout from the one screen that fixes everything else", secondsLeft)
	}

	// And the unlock endpoint says so plainly instead of asking for a code.
	status, body := postFactorAs(t, pool, r, "/api/admin/permissions/unlock", actor.id,
		map[string]any{"code": "123456"})
	if status != statusPermSectionLocked {
		t.Fatalf("unlock status = %d, want 423 (body: %v)", status, body)
	}
	if got, _ := body["code"].(string); got != "perm_section_blocked_wait" {
		t.Errorf("unlock code = %q, want perm_section_blocked_wait (body: %v)", got, body)
	}
	if bySMS, _ := body["unlock_by_sms"].(bool); bySMS {
		t.Error("unlock_by_sms = true when no SMS was sent — the response is claiming a message that never left")
	}
}

// TestPermissionBurstUnlocksBySMS is the client's own way out: a code is texted,
// and only that code lifts the freeze.
func TestPermissionBurstUnlocksBySMS(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("PERM_BURST_MAX", "2")
	t.Setenv("PERM_BURST_WINDOW_SECONDS", "60")

	stub := newFakeOTPIQ(t)
	t.Setenv("OTPIQ_API_KEY", "sk_test_fake")
	t.Setenv("OTPIQ_BASE_URL", stub.server.URL)

	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	clearBurstState(t, pool, actor.id)
	r := newBurstRouter(pool, auth.NewOTPIQClient(), nil)

	for i := 0; i < 3; i++ {
		if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[i], false); status != http.StatusOK {
			t.Fatalf("change %d: status = %d (body: %v)", i+1, status, body)
		}
	}

	sent := stub.sent()
	if len(sent) != 1 {
		t.Fatalf("unlock SMS sent = %d, want 1", len(sent))
	}
	unlockCode := sent[0]

	// Frozen, and this time the refusal points at the code.
	status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[5], false)
	if status != statusPermSectionLocked {
		t.Fatalf("status = %d, want 423 (body: %v)", status, body)
	}
	if got, _ := body["code"].(string); got != "perm_section_blocked_sms" {
		t.Errorf("code = %q, want perm_section_blocked_sms (body: %v)", got, body)
	}

	// A wrong code lifts nothing.
	if status, body := postFactorAs(t, pool, r, "/api/admin/permissions/unlock", actor.id,
		map[string]any{"code": "000000"}); status != http.StatusUnauthorized {
		t.Errorf("wrong-code unlock status = %d, want 401 (body: %v)", status, body)
	}
	if status, _ := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[6], false); status != statusPermSectionLocked {
		t.Errorf("a wrong unlock code lifted the freeze (status = %d)", status)
	}

	// The real one does.
	if status, body := postFactorAs(t, pool, r, "/api/admin/permissions/unlock", actor.id,
		map[string]any{"code": unlockCode}); status != http.StatusOK {
		t.Fatalf("unlock status = %d, want 200 (body: %v)", status, body)
	}
	// Straight back to work, with the burst's audit rows left exactly where they
	// are. The first draft of this case had to DELETE them here or the next
	// change re-tripped the freeze instantly; that deletion was covering for the
	// defect TestPermissionBurstUnlockLetsWorkResume now pins.
	if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[7], false); status != http.StatusOK {
		t.Errorf("status = %d after a valid unlock, want 200 (body: %v)", status, body)
	}
}

// ─── The gaps found auditing the first draft of this row ────────────────
//
// The four cases below were written against the partial implementation and each
// one failed on it. They are the difference between a block that exists and a
// block that works.

// TestPermissionBurstUnlockGoesByEmail is the channel the first draft forgot.
//
// H20 landed a working SMTP sender (internal/auth/mailer.go) and main.go already
// hands it to THIS handler — the H1 second factor on this very screen uses it.
// The unlock code did not. On a deployment with a mail relay and no SMS gateway
// the block therefore reported "no channel could be reached" while a perfectly
// good channel sat unused, and downgraded itself to a short cooldown it did not
// need to be.
func TestPermissionBurstUnlockGoesByEmail(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("PERM_BURST_MAX", "2")
	t.Setenv("PERM_BURST_WINDOW_SECONDS", "60")

	smtpStub := newFakeSMTP(t)
	mailer := auth.NewMailer(auth.MailerConfig{
		Host: "127.0.0.1", Port: smtpStub.port(), From: "no-reply@test.local",
	})
	if mailer == nil {
		t.Fatal("NewMailer returned nil for a fully configured mailer")
	}

	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	setEmail(t, pool, actor.id, "owner@test.local")
	clearBurstState(t, pool, actor.id)
	r := newBurstRouter(pool, nil, mailer) // email is real, SMS is not

	for i := 0; i < 3; i++ {
		if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[i], false); status != http.StatusOK {
			t.Fatalf("change %d: status = %d (body: %v)", i+1, status, body)
		}
	}

	bodies := smtpStub.decodedBodies()
	if len(bodies) != 1 {
		t.Fatalf("unlock emails sent = %d, want 1 — the block ignored the one channel it had", len(bodies))
	}
	unlockCode := codeFrom(t, bodies[0])

	// The row has to say WHICH channel carried it, or the operator cannot tell
	// where to go looking for the code.
	var channel *string
	var hash *string
	if err := pool.QueryRow(context.Background(),
		`SELECT unlock_channel, unlock_code_hash FROM permission_section_blocks
		  WHERE actor_user_id = $1`, actor.id).Scan(&channel, &hash); err != nil {
		t.Fatalf("read the block: %v", err)
	}
	if channel == nil || *channel != "email" {
		t.Errorf("unlock_channel = %v, want \"email\"", channel)
	}
	if hash == nil || *hash == "" {
		t.Error("no unlock code was recorded even though one was emailed")
	}

	// The refusal has to point at the inbox, not at a phone that got nothing.
	status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[5], false)
	if status != statusPermSectionLocked {
		t.Fatalf("status = %d, want 423 (body: %v)", status, body)
	}
	if got, _ := body["code"].(string); got != "perm_section_blocked_email" {
		t.Errorf("code = %q, want perm_section_blocked_email (body: %v)", got, body)
	}

	// And the emailed code lifts it.
	if status, body := postFactorAs(t, pool, r, "/api/admin/permissions/unlock", actor.id,
		map[string]any{"code": unlockCode}); status != http.StatusOK {
		t.Fatalf("unlock status = %d, want 200 (body: %v)", status, body)
	}
}

// TestPermissionBurstCountsOnlyRealChanges stops the detector counting its own
// output.
//
// The counter is a COUNT over permission_audit_log by actor — and tripping the
// block appends a row to permission_audit_log under that same actor, as does
// lifting it. Unfiltered, the mechanism inflates its own evidence: every trip
// pushes the actor closer to the next one for something they did not do.
func TestPermissionBurstCountsOnlyRealChanges(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	clearBurstState(t, pool, actor.id)

	h := &AdminPermissionsHandler{Perms: permissions.New(pool)}
	ctx := context.Background()
	id := actor.id

	// Two genuine changes…
	for _, action := range []string{"permission_set", "user_permission_set"} {
		if err := h.Perms.LogAudit(ctx, &id, action, "supervisor/reports/view",
			"allowed", "denied", "127.0.0.1"); err != nil {
			t.Fatalf("seed %s: %v", action, err)
		}
	}
	// …and five rows this feature writes about ITSELF.
	for i := 0; i < 5; i++ {
		if err := h.Perms.LogAudit(ctx, &id, permBlockAuditAction, "actor#x",
			"9 changes/1m0s", "blocked", "127.0.0.1"); err != nil {
			t.Fatalf("seed block row: %v", err)
		}
		if err := h.Perms.LogAudit(ctx, &id, permUnlockAuditAction, "actor#x",
			"blocked", "unblocked", "127.0.0.1"); err != nil {
			t.Fatalf("seed unblock row: %v", err)
		}
	}

	if got := h.recentChangeCount(ctx, actor.id, time.Minute); got != 2 {
		t.Errorf("recentChangeCount = %d, want 2 — the detector is counting the "+
			"block and unblock rows it wrote itself", got)
	}
}

// TestPermissionBurstUnlockLetsWorkResume is the one that makes the unlock mean
// something.
//
// The counter is a sliding window over the audit trail, so the moment the code
// is accepted every change from the burst is STILL inside that window. The very
// next change therefore crosses the threshold again and re-freezes the section —
// and sends a second code, at real SMS cost, for one click. An unlock that does
// not let you work is not an unlock; the count has to start again from the trip.
func TestPermissionBurstUnlockLetsWorkResume(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("PERM_BURST_MAX", "2")
	t.Setenv("PERM_BURST_WINDOW_SECONDS", "3600") // an hour: the burst cannot age out

	stub := newFakeOTPIQ(t)
	t.Setenv("OTPIQ_API_KEY", "sk_test_fake")
	t.Setenv("OTPIQ_BASE_URL", stub.server.URL)

	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	clearBurstState(t, pool, actor.id)
	r := newBurstRouter(pool, auth.NewOTPIQClient(), nil)

	for i := 0; i < 3; i++ {
		if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[i], false); status != http.StatusOK {
			t.Fatalf("change %d: status = %d (body: %v)", i+1, status, body)
		}
	}
	sent := stub.sent()
	if len(sent) != 1 {
		t.Fatalf("unlock codes sent = %d, want 1", len(sent))
	}

	if status, body := postFactorAs(t, pool, r, "/api/admin/permissions/unlock", actor.id,
		map[string]any{"code": sent[0]}); status != http.StatusOK {
		t.Fatalf("unlock status = %d, want 200 (body: %v)", status, body)
	}

	// No hand-clearing of the audit trail here, deliberately: that is the
	// production shape, and a test that has to delete rows to stay green is
	// describing the defect rather than pinning the fix.
	if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[5], false); status != http.StatusOK {
		t.Fatalf("status = %d after a valid unlock, want 200 — the freeze came "+
			"straight back on the burst it was just lifted from (body: %v)", status, body)
	}
	if got := len(stub.sent()); got != 1 {
		t.Errorf("codes sent = %d, want 1 — the re-trip billed the owner for a "+
			"second SMS after they had already unlocked", got)
	}
	// The change above is applied BEFORE the counter runs, so a silent re-freeze
	// shows up only on the one after it. That is the click where the operator
	// discovers their unlock bought them exactly one action.
	if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[6], false); status != http.StatusOK {
		t.Errorf("status = %d on the second change after unlocking, want 200 — "+
			"the unlock bought a single click before the freeze returned (body: %v)", status, body)
	}
}

// TestPermissionBlockSharesTheDatabaseClock catches a defect that only appears
// away from UTC, which is to say on the server this system actually runs on.
//
// permission_audit_log.created_at is stamped by Postgres (CURRENT_TIMESTAMP into
// a naive column, i.e. the database's LOCAL wall clock). The first draft of the
// block wrote blocked_at/expires_at from Go in UTC into the same kind of column.
// On the deployment timezone, Asia/Baghdad, two rows written a millisecond apart
// therefore land three hours apart, and any comparison across the two tables —
// which is exactly what "count the changes since this actor was blocked" is —
// silently reads the wrong side of the gap. One database, one clock.
func TestPermissionBlockSharesTheDatabaseClock(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("PERM_BURST_MAX", "2")
	t.Setenv("PERM_BURST_WINDOW_SECONDS", "60")

	actor := insertAccount(t, pool, "super_admin", "TheOwnersPassword1")
	clearBurstState(t, pool, actor.id)
	r := newBurstRouter(pool, nil, nil)

	for i := 0; i < 3; i++ {
		if status, body := changeAs(t, pool, r, actor, "TheOwnersPassword1", burstModules[i], false); status != http.StatusOK {
			t.Fatalf("change %d: status = %d (body: %v)", i+1, status, body)
		}
	}

	var skew float64
	if err := pool.QueryRow(context.Background(),
		`SELECT EXTRACT(EPOCH FROM (
		          (SELECT MAX(created_at) FROM permission_audit_log WHERE actor_id = $1)
		          - (SELECT blocked_at FROM permission_section_blocks WHERE actor_user_id = $1)))`,
		actor.id).Scan(&skew); err != nil {
		t.Fatalf("measure clock skew: %v", err)
	}
	if skew < -60 || skew > 60 {
		t.Errorf("blocked_at is %.0f seconds from the audit row written beside it — "+
			"the block is on a different clock from the trail it counts", skew)
	}

	// The same clock has to reach expires_at, or "how long until this lapses"
	// is wrong by the UTC offset for anyone reading the row.
	var remaining float64
	if err := pool.QueryRow(context.Background(),
		`SELECT EXTRACT(EPOCH FROM (expires_at - CURRENT_TIMESTAMP))
		   FROM permission_section_blocks WHERE actor_user_id = $1`, actor.id).Scan(&remaining); err != nil {
		t.Fatalf("measure remaining: %v", err)
	}
	if remaining <= 0 {
		t.Errorf("expires_at is already in the past by the database's own clock (%.0fs) — "+
			"the freeze reads as over the instant it starts", remaining)
	}
}
