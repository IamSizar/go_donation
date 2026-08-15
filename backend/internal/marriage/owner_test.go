// owner_test.go — K14: the three controls a خطوبتي profile owner never had.
//
// # WHY THIS FILE EXISTS
//
// The client's spec asks for "a profile with edit / activate / delete-account".
// The app shipped none of the three, and was right not to: `POST /api/marriage`
// INSERTS a row with a freshly generated profile_code — it is a second
// submission, not an update — and there was no PATCH, no PUT and no DELETE a
// profile's owner could call. internal/marriage had exactly one owner-scoped
// mutation, SetFieldPrivacy. The app says so in writing, in
// marriage_my_profile_screen.dart, where the button is deliberately NOT called
// "edit" because "calling it 'edit' ... promised something the app cannot do".
//
// These tests are what makes the three buttons honest. Every one of them checks
// the same two properties, because both are ways the feature could be wrong:
//
//  1. THE OWNER'S ACTION TAKES EFFECT — the edit is stored, the paused profile
//     leaves the browse feed, the deleted profile leaves every app surface.
//  2. NOBODY ELSE'S DOES — ownership is checked INSIDE each UPDATE/DELETE, not
//     in the handler, so there is no window between the check and the write,
//     and a stranger's request changes nothing at all.
//
// The delete deserves its own note. It does NOT remove the row, and
// TestOwnerDeleteKeepsTheChatsAndThePaymentRecord pins why: marriage_profiles
// has two ON DELETE CASCADE children — marriage_chat_threads (and through it
// every message) and marriage_subscription_purchases, the record that a user
// PAID. handlers.trashRow archives only the row it deletes, so a real delete
// would destroy both and no Trash restore could bring them back. See owner.go.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set, so
// `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_k14        # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k14?sslmode=disable' \
//	  go test ./internal/marriage/ -run Owner -v
package marriage

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Harness ────────────────────────────────────────────────────────────
//
// newTestPool / makeUser / makeProfile / find / contains are shared with
// field_privacy_test.go — same package, same fixtures, one harness.

func strPtr(s string) *string { return &s }
func numPtr(n int) *int       { return &n }

// browse is what a stranger sees.
func browse(t *testing.T, pool *pgxpool.Pool, viewer int64) []Profile {
	t.Helper()
	items, err := New(pool).List(context.Background(), SearchFilters{ViewerUserID: viewer, Limit: 100})
	if err != nil {
		t.Fatalf("List(browse): %v", err)
	}
	return items
}

// mine is what /api/marriage/mine serves the owner: every status, unfiltered.
func mine(t *testing.T, pool *pgxpool.Pool, owner int64) []Profile {
	t.Helper()
	items, err := New(pool).List(context.Background(), SearchFilters{
		Status: "all", OwnedByUser: owner, ViewerUserID: owner,
	})
	if err != nil {
		t.Fatalf("List(mine): %v", err)
	}
	return items
}

// readStatus goes straight to the column, so a test can tell "hidden from the
// app" apart from "gone from the database".
func readStatus(t *testing.T, pool *pgxpool.Pool, id int64) (status string, ownerDeleted bool) {
	t.Helper()
	var deletedAt *string
	if err := pool.QueryRow(context.Background(),
		`SELECT status, owner_deleted_at::text FROM marriage_profiles WHERE id = $1`, id,
	).Scan(&status, &deletedAt); err != nil {
		t.Fatalf("read profile %d: %v", id, err)
	}
	return status, deletedAt != nil
}

// ─── تعديل — edit ───────────────────────────────────────────────────────

func TestOwnerCanEditTheirOwnProfile(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	if err := New(pool).UpdateOwnProfile(context.Background(), id, owner, OwnerProfilePatch{
		City:            strPtr("Duhok"),
		Age:             numPtr(31),
		SocialSummary:   strPtr("a rewritten summary"),
		VisibilityLevel: strPtr("private"),
	}); err != nil {
		t.Fatalf("UpdateOwnProfile: %v", err)
	}

	p := find(t, mine(t, pool, owner), id)
	if p.City == nil || *p.City != "Duhok" {
		t.Errorf("city = %v, want Duhok", p.City)
	}
	if p.Age == nil || *p.Age != 31 {
		t.Errorf("age = %v, want 31", p.Age)
	}
	if p.SocialSummary == nil || *p.SocialSummary != "a rewritten summary" {
		t.Errorf("social_summary = %v, want the new text", p.SocialSummary)
	}
	if p.VisibilityLevel != "private" {
		t.Errorf("visibility_level = %q, want private", p.VisibilityLevel)
	}
	// Fields the patch did not mention must survive. A PATCH that blanked
	// everything it was not told about would lose a profile on every edit.
	if p.Gender == nil || *p.Gender != "female" {
		t.Errorf("gender = %v — it was not in the patch and must be untouched", p.Gender)
	}
	if p.HeightCm == nil || *p.HeightCm != 165 {
		t.Errorf("height_cm = %v — it was not in the patch and must be untouched", p.HeightCm)
	}
}

// An empty string is how the owner CLEARS an optional field, and it has to be
// distinguishable from "not sent" or the picker can never un-set anything.
func TestOwnerEditClearsAFieldWithAnEmptyValue(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	if err := New(pool).UpdateOwnProfile(context.Background(), id, owner, OwnerProfilePatch{
		Religion: strPtr(""), WeightKg: numPtr(0),
	}); err != nil {
		t.Fatalf("UpdateOwnProfile: %v", err)
	}
	p := find(t, mine(t, pool, owner), id)
	if p.Religion != nil {
		t.Errorf("religion = %v after being cleared, want nil", p.Religion)
	}
	if p.WeightKg != nil {
		t.Errorf("weight_kg = %v after being cleared, want nil", p.WeightKg)
	}
}

// The whole point of an owner-scoped endpoint.
func TestOwnerEditRefusesAStrangerAndWritesNothing(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	stranger := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	err := New(pool).UpdateOwnProfile(context.Background(), id, stranger,
		OwnerProfilePatch{City: strPtr("Somewhere Else")})
	if !errors.Is(err, ErrNotOwner) {
		t.Fatalf("UpdateOwnProfile by a stranger returned %v, want ErrNotOwner", err)
	}
	if p := find(t, mine(t, pool, owner), id); p.City == nil || *p.City != "Erbil" {
		t.Errorf("city = %v after a rejected write, want the original Erbil", p.City)
	}
}

// A missing profile answers exactly like somebody else's, so the endpoint
// cannot be used to probe which ids exist. Same rule as SetFieldPrivacy.
func TestOwnerEditOnAMissingProfileLooksTheSame(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	if err := New(pool).UpdateOwnProfile(context.Background(), 999999999, owner,
		OwnerProfilePatch{City: strPtr("Erbil")}); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("UpdateOwnProfile on a missing profile returned %v, want ErrNotOwner", err)
	}
}

// Moderation boundary: the owner edits their own details, and staff decide
// whether the profile is active. An owner-writable status would be a
// self-approval route into the browse feed.
func TestOwnerEditCannotTouchStatusOrSubscription(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)
	before := find(t, mine(t, pool, owner), id)

	if err := New(pool).UpdateOwnProfile(context.Background(), id, owner,
		OwnerProfilePatch{City: strPtr("Duhok")}); err != nil {
		t.Fatalf("UpdateOwnProfile: %v", err)
	}
	after := find(t, mine(t, pool, owner), id)
	if after.Status != before.Status {
		t.Errorf("status changed from %q to %q on an ordinary edit", before.Status, after.Status)
	}
	if after.SubscriptionStatus != before.SubscriptionStatus {
		t.Errorf("subscription_status changed from %q to %q on an ordinary edit",
			before.SubscriptionStatus, after.SubscriptionStatus)
	}
	if after.ProfileCode != before.ProfileCode {
		t.Errorf("profile_code changed on an edit — it is the handle that stands in for a name")
	}
}

// An invalid audience is refused rather than quietly coerced. Insert falls back
// to a default because it has to produce a row from a partial form; an explicit
// edit is a decision, and silently storing a different privacy level than the
// one the user picked is the exact failure this wave exists to remove.
func TestOwnerEditRejectsAnUnknownVisibility(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	err := New(pool).UpdateOwnProfile(context.Background(), id, owner,
		OwnerProfilePatch{VisibilityLevel: strPtr("everyone")})
	if err == nil || errors.Is(err, ErrNotOwner) {
		t.Fatalf("UpdateOwnProfile with visibility_level=everyone returned %v, want a validation error", err)
	}
	if p := find(t, mine(t, pool, owner), id); p.VisibilityLevel != "matched_summary" {
		t.Errorf("visibility_level = %q after a rejected edit, want the original", p.VisibilityLevel)
	}
}

// A patch with nothing in it is a no-op, not an error and not a blanked row.
func TestOwnerEditWithNothingToChangeIsHarmless(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	if err := New(pool).UpdateOwnProfile(context.Background(), id, owner, OwnerProfilePatch{}); err != nil {
		t.Fatalf("empty UpdateOwnProfile returned %v, want no error", err)
	}
	if p := find(t, mine(t, pool, owner), id); p.City == nil || *p.City != "Erbil" {
		t.Errorf("an empty patch changed the row: city = %v", p.City)
	}
}

// ─── إيقاف / تفعيل — pause and resume ───────────────────────────────────

func TestOwnerPauseHidesTheProfileAndResumeBringsItBack(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	viewer := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil) // seeded 'active'

	if err := New(pool).PauseOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("PauseOwnProfile: %v", err)
	}
	if contains(t, browse(t, pool, viewer), id) {
		t.Errorf("a paused profile is still in the browse feed")
	}
	// The owner must still see it, or they can never turn it back on.
	p := find(t, mine(t, pool, owner), id)
	if p.Status != "paused" {
		t.Errorf("status = %q after pause, want paused", p.Status)
	}

	if err := New(pool).ResumeOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("ResumeOwnProfile: %v", err)
	}
	if !contains(t, browse(t, pool, viewer), id) {
		t.Errorf("a resumed profile did not come back to the browse feed")
	}
	if p := find(t, mine(t, pool, owner), id); p.Status != "active" {
		t.Errorf("status = %q after resume, want the 'active' it was before the pause", p.Status)
	}
}

// THE ESCALATION THIS PREVENTS. A profile awaiting review is browsable but not
// yet approved. If resume always wrote 'active', pausing and resuming would be
// a one-tap route from "submitted" to "approved by nobody".
func TestOwnerResumeRestoresTheStatusItPausedFromNotActive(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)
	if _, err := pool.Exec(context.Background(),
		`UPDATE marriage_profiles SET status = 'submitted' WHERE id = $1`, id); err != nil {
		t.Fatalf("set fixture status: %v", err)
	}

	s := New(pool)
	if err := s.PauseOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("PauseOwnProfile: %v", err)
	}
	if err := s.ResumeOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("ResumeOwnProfile: %v", err)
	}
	if got, _ := readStatus(t, pool, id); got != "submitted" {
		t.Errorf("status = %q after pause+resume of a SUBMITTED profile, want submitted — "+
			"resuming must not approve a profile staff have not reviewed", got)
	}
}

// A rejected profile is not the owner's to switch back on.
func TestOwnerCannotPauseARejectedProfile(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)
	if _, err := pool.Exec(context.Background(),
		`UPDATE marriage_profiles SET status = 'rejected' WHERE id = $1`, id); err != nil {
		t.Fatalf("set fixture status: %v", err)
	}

	if err := New(pool).PauseOwnProfile(context.Background(), id, owner); !errors.Is(err, ErrNotPausable) {
		t.Fatalf("PauseOwnProfile on a rejected profile returned %v, want ErrNotPausable", err)
	}
	if got, _ := readStatus(t, pool, id); got != "rejected" {
		t.Errorf("status = %q after a refused pause, want rejected", got)
	}
}

func TestOwnerPauseAndResumeRefuseAStranger(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	stranger := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	if err := New(pool).PauseOwnProfile(context.Background(), id, stranger); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("PauseOwnProfile by a stranger returned %v, want ErrNotOwner", err)
	}
	if got, _ := readStatus(t, pool, id); got != "active" {
		t.Fatalf("status = %q after a stranger's pause, want active", got)
	}
	if err := New(pool).PauseOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("PauseOwnProfile: %v", err)
	}
	if err := New(pool).ResumeOwnProfile(context.Background(), id, stranger); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("ResumeOwnProfile by a stranger returned %v, want ErrNotOwner", err)
	}
	if got, _ := readStatus(t, pool, id); got != "paused" {
		t.Errorf("status = %q after a stranger's resume, want it still paused", got)
	}
}

// ─── حذف — recoverable delete ───────────────────────────────────────────

func TestOwnerDeleteRemovesTheProfileFromEveryAppSurface(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	viewer := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO marriage_saved (user_id, profile_id) VALUES ($1, $2)`, viewer, id); err != nil {
		t.Fatalf("bookmark fixture: %v", err)
	}

	if err := New(pool).DeleteOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("DeleteOwnProfile: %v", err)
	}
	if contains(t, browse(t, pool, viewer), id) {
		t.Errorf("a deleted profile is still in the browse feed")
	}
	if contains(t, mine(t, pool, owner), id) {
		t.Errorf("a deleted profile is still in its owner's own list")
	}
	saved, err := New(pool).List(context.Background(), SearchFilters{
		Status: "all", SavedByUser: viewer, ViewerUserID: viewer,
	})
	if err != nil {
		t.Fatalf("List(saved): %v", err)
	}
	if contains(t, saved, id) {
		t.Errorf("a deleted profile is still in somebody's bookmarks — it has to disappear " +
			"from every surface, not just the one the owner was looking at")
	}
}

// THE REASON THIS IS NOT A ROW DELETE. handlers.trashRow archives only the row
// it removes; marriage_profiles' children cascade and are NOT archived. A real
// delete would take the user's mediated chats and — worse — the record that
// they paid for a subscription, and no Trash restore could bring either back.
func TestOwnerDeleteKeepsTheChatsAndThePaymentRecord(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()
	owner := makeUser(t, pool)
	requester := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	var reqID, threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id, message)
		 VALUES ($1, $2, 'hello') RETURNING id`, requester, id).Scan(&reqID); err != nil {
		t.Fatalf("meeting request fixture: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_chat_threads
		   (meeting_request_id, profile_id, requester_user_id, owner_user_id, status)
		 VALUES ($1, $2, $3, $4, 'active') RETURNING id`,
		reqID, id, requester, owner).Scan(&threadID); err != nil {
		t.Fatalf("chat thread fixture: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO marriage_chat_messages (thread_id, sender_user_id, sender_role, body)
		 VALUES ($1, $2, 'requester', 'a message that must survive')`, threadID, requester); err != nil {
		t.Fatalf("chat message fixture: %v", err)
	}
	var pkgID int64
	if err := pool.QueryRow(ctx,
		`SELECT id FROM marriage_subscription_packages ORDER BY display_order, id LIMIT 1`,
	).Scan(&pkgID); err != nil {
		t.Fatalf("read a subscription package: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO marriage_subscription_purchases
		   (profile_id, user_id, package_id, price_iqd, payment_method, status)
		 VALUES ($1, $2, $3, 25000, 'app_wallet', 'paid')`, id, owner, pkgID); err != nil {
		t.Fatalf("subscription purchase fixture: %v", err)
	}

	if err := New(pool).DeleteOwnProfile(ctx, id, owner); err != nil {
		t.Fatalf("DeleteOwnProfile: %v", err)
	}

	count := func(sql string, args ...any) int {
		t.Helper()
		var n int
		if err := pool.QueryRow(ctx, sql, args...).Scan(&n); err != nil {
			t.Fatalf("count: %v", err)
		}
		return n
	}
	if n := count(`SELECT COUNT(*) FROM marriage_profiles WHERE id = $1`, id); n != 1 {
		t.Fatalf("the profile row was removed — the children cascade and cannot be restored")
	}
	if n := count(`SELECT COUNT(*) FROM marriage_chat_messages WHERE thread_id = $1`, threadID); n != 1 {
		t.Errorf("the mediated chat history was destroyed by a profile delete")
	}
	if n := count(`SELECT COUNT(*) FROM marriage_subscription_purchases WHERE profile_id = $1`, id); n != 1 {
		t.Errorf("the record that this user PAID for a subscription was destroyed by a profile delete")
	}
	// And it is marked, so staff can tell a self-deletion from a staff closure.
	status, ownerDeleted := readStatus(t, pool, id)
	if !ownerDeleted {
		t.Errorf("owner_deleted_at was not stamped — staff cannot tell this apart from a closure they made")
	}
	if status != "closed" {
		t.Errorf("status = %q after an owner delete, want closed", status)
	}
}

func TestOwnerDeleteRefusesAStranger(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	stranger := makeUser(t, pool)
	viewer := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	if err := New(pool).DeleteOwnProfile(context.Background(), id, stranger); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("DeleteOwnProfile by a stranger returned %v, want ErrNotOwner", err)
	}
	if !contains(t, browse(t, pool, viewer), id) {
		t.Errorf("a stranger's delete removed the profile from the browse feed anyway")
	}
}

// Deleting twice is not an error the app has to explain — the second one just
// finds nothing left to delete, and says so the same way a stranger would be
// told, so the endpoint still leaks nothing.
func TestOwnerDeleteIsIdempotentFromTheOwnersPointOfView(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	s := New(pool)
	if err := s.DeleteOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("first DeleteOwnProfile: %v", err)
	}
	if err := s.DeleteOwnProfile(context.Background(), id, owner); !errors.Is(err, ErrNotOwner) {
		t.Fatalf("second DeleteOwnProfile returned %v, want ErrNotOwner", err)
	}
}

// An owner-deleted profile is out of reach of the owner's own controls too —
// otherwise "delete" would leave a row they could still edit and un-pause.
func TestOwnerCannotEditOrPauseADeletedProfile(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)
	if err := New(pool).DeleteOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("DeleteOwnProfile: %v", err)
	}

	if err := New(pool).UpdateOwnProfile(context.Background(), id, owner,
		OwnerProfilePatch{City: strPtr("Duhok")}); !errors.Is(err, ErrNotOwner) {
		t.Errorf("UpdateOwnProfile on a deleted profile returned %v, want ErrNotOwner", err)
	}
	if err := New(pool).PauseOwnProfile(context.Background(), id, owner); err == nil {
		t.Errorf("PauseOwnProfile on a deleted profile succeeded")
	}
}

// The restore path. Staff clear the stamp — see AdminStatusHandler.Marriage,
// which does it on every status decision — and the profile is whole again,
// with its chats and its payment record still attached.
func TestStaffClearingTheStampRestoresTheProfile(t *testing.T) {
	pool := newTestPool(t)
	owner := makeUser(t, pool)
	viewer := makeUser(t, pool)
	id := makeProfile(t, pool, owner, "matched_summary", nil)

	if err := New(pool).DeleteOwnProfile(context.Background(), id, owner); err != nil {
		t.Fatalf("DeleteOwnProfile: %v", err)
	}
	if _, err := pool.Exec(context.Background(),
		`UPDATE marriage_profiles SET owner_deleted_at = NULL, status = 'active' WHERE id = $1`, id,
	); err != nil {
		t.Fatalf("staff restore: %v", err)
	}
	if !contains(t, browse(t, pool, viewer), id) {
		t.Errorf("a restored profile did not come back to the browse feed")
	}
	if !contains(t, mine(t, pool, owner), id) {
		t.Errorf("a restored profile did not come back to its owner's list")
	}
}
