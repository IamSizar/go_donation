// Package handlers tests — the ADMIN engagement-profile delete.
//
// K14 (commit 9f6ec79) refused to route marriage_profiles through trashRow for
// the OWNER's own حذف, because the row cascades to
//
//	marriage_profiles
//	  ├─ marriage_chat_threads  →  _messages, _reads
//	  └─ marriage_subscription_purchases   ← the record that the user PAID
//
// and trashRow archives only the row it deletes. internal/marriage/owner.go
// stamps owner_deleted_at instead and says so at length. The STAFF route kept
// going through trashRow, so the hazard K14 documents stayed live on the admin
// side — a protection reported as shipped that was half missing.
//
// The rule pinned here: neither door destroys a mediated conversation or the
// record of a payment.
//
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h10?sslmode=disable' \
//	  go test -p 1 ./internal/handlers/ -run MarriageDelete
package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Fixtures ───────────────────────────────────────────────────────────

// marriageRecordsFixture is one engagement profile plus what a delete cascades.
type marriageRecordsFixture struct {
	profileID int64
	threadID  int64
}

// makeMarriageProfileWithRecords builds a profile carrying `messages` mediated
// chat messages and `purchases` subscription payments. Both may be 0, which is
// the profile that must STILL be deletable.
func makeMarriageProfileWithRecords(t *testing.T, pool *pgxpool.Pool, messages, purchases int) marriageRecordsFixture {
	t.Helper()
	ctx := context.Background()

	owner := insertAccount(t, pool, "user", "")
	requester := insertAccount(t, pool, "user", "")

	var profileID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_profiles (user_id, profile_code, status)
		 VALUES ($1, $2, 'active') RETURNING id`,
		owner.id, fmt.Sprintf("MARRIAGE-GUARD-%d", owner.id),
	).Scan(&profileID); err != nil {
		t.Fatalf("insert engagement profile: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM trash_items WHERE source_table = 'marriage_profiles' AND row_id = $1`, profileID)
		_, _ = pool.Exec(bg, `DELETE FROM marriage_profiles WHERE id = $1`, profileID)
	})

	// The thread staff open when they approve a meeting request — it exists
	// before anyone has typed, which is why the guard counts messages.
	var meetingID, threadID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_meeting_requests (from_user_id, profile_id, status)
		 VALUES ($1, $2, 'approved') RETURNING id`, requester.id, profileID,
	).Scan(&meetingID); err != nil {
		t.Fatalf("insert meeting request: %v", err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO marriage_chat_threads (meeting_request_id, profile_id, requester_user_id, owner_user_id)
		 VALUES ($1, $2, $3, $4) RETURNING id`, meetingID, profileID, requester.id, owner.id,
	).Scan(&threadID); err != nil {
		t.Fatalf("insert marriage chat thread: %v", err)
	}
	for i := 0; i < messages; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO marriage_chat_messages (thread_id, sender_user_id, sender_role, body)
			 VALUES ($1, $2, 'requester', 'message worth keeping')`, threadID, requester.id); err != nil {
			t.Fatalf("insert marriage chat message: %v", err)
		}
	}

	if purchases > 0 {
		var packageID int64
		if err := pool.QueryRow(ctx,
			`INSERT INTO marriage_subscription_packages (slug, name_en)
			 VALUES ($1, 'guard fixture package') RETURNING id`,
			fmt.Sprintf("marriage-guard-%d", profileID),
		).Scan(&packageID); err != nil {
			t.Fatalf("insert subscription package: %v", err)
		}
		t.Cleanup(func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM marriage_subscription_packages WHERE id = $1`, packageID)
		})
		for i := 0; i < purchases; i++ {
			if _, err := pool.Exec(ctx,
				`INSERT INTO marriage_subscription_purchases
				   (profile_id, user_id, package_id, price_iqd, payment_method, status, transaction_code)
				 VALUES ($1, $2, $3, 30000, 'wallet', 'paid', $4)`,
				profileID, owner.id, packageID, fmt.Sprintf("GUARD-TXN-%d-%d", profileID, i)); err != nil {
				t.Fatalf("insert subscription purchase: %v", err)
			}
		}
	}

	return marriageRecordsFixture{profileID: profileID, threadID: threadID}
}

// countMarriageMessages reports how much of the mediated conversation survives.
func countMarriageMessages(t *testing.T, pool *pgxpool.Pool, threadID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM marriage_chat_messages WHERE thread_id = $1`, threadID).Scan(&n); err != nil {
		t.Fatalf("count marriage messages: %v", err)
	}
	return n
}

// countMarriagePurchases reports how many payment records survive.
func countMarriagePurchases(t *testing.T, pool *pgxpool.Pool, profileID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM marriage_subscription_purchases WHERE profile_id = $1`, profileID).Scan(&n); err != nil {
		t.Fatalf("count marriage purchases: %v", err)
	}
	return n
}

// ─── The rule ───────────────────────────────────────────────────────────

// TestMarriageDeleteRefusesWhenItWouldDestroyRecords is the half of K14 that
// was never applied. Before this guard the staff route answered 200
// "trashed": true and both the conversation and the payment were gone.
func TestMarriageDeleteRefusesWhenItWouldDestroyRecords(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	f := makeMarriageProfileWithRecords(t, pool, 2, 1)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).Marriage, f.profileID)

	if status != http.StatusConflict {
		t.Errorf("status = %d, want 409 — the staff route must refuse the delete K14 refused for the owner (body: %s)", status, body)
	}
	var profileStillThere bool
	if err := pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM marriage_profiles WHERE id = $1)`, f.profileID).Scan(&profileStillThere); err != nil {
		t.Fatalf("check profile: %v", err)
	}
	if !profileStillThere {
		t.Error("the profile was deleted despite the refusal")
	}
	if n := countMarriageMessages(t, pool, f.threadID); n != 2 {
		t.Errorf("%d of 2 messages survived — the mediated conversation was destroyed", n)
	}
	if n := countMarriagePurchases(t, pool, f.profileID); n != 1 {
		t.Errorf("%d of 1 subscription purchases survived — the record that the user PAID was destroyed", n)
	}
	if n := trashCountFor(t, pool, "marriage_profiles", f.profileID); n != 0 {
		t.Errorf("%d trash entries for a refused delete, want 0", n)
	}
}

// TestMarriageDeleteRefusalTellsTheOperatorWhy — the refusal must be
// actionable and localisable, like every other one in this dashboard.
func TestMarriageDeleteRefusalTellsTheOperatorWhy(t *testing.T) {
	pool := newAuthTestPool(t)

	f := makeMarriageProfileWithRecords(t, pool, 3, 2)

	_, body := callDelete(t, NewAdminDeleteHandler(pool).Marriage, f.profileID)

	var resp struct {
		Success   bool   `json:"success"`
		Error     string `json:"error"`
		Code      string `json:"code"`
		Messages  int    `json:"messages"`
		Purchases int    `json:"subscription_purchases"`
	}
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("unmarshal refusal body %q: %v", body, err)
	}
	if resp.Success {
		t.Error("success = true on a refused delete")
	}
	if resp.Code != "marriage_profile_has_records" {
		t.Errorf("code = %q, want marriage_profile_has_records — the dashboard keys its localised message off this", resp.Code)
	}
	if resp.Messages != 3 {
		t.Errorf("messages = %d, want 3", resp.Messages)
	}
	if resp.Purchases != 2 {
		t.Errorf("subscription_purchases = %d, want 2", resp.Purchases)
	}
	if resp.Error == "" {
		t.Error("no fallback message; a client without the code mapping would show nothing")
	}
}

// TestMarriageDeleteStillWorksWithAnEmptyThread — staff open the mediated
// thread when they approve a meeting request, before either side has typed.
// Refusing on the thread rather than on its messages would have blocked every
// profile that ever had a meeting approved.
func TestMarriageDeleteStillWorksWithAnEmptyThread(t *testing.T) {
	pool := newAuthTestPool(t)
	ctx := context.Background()

	f := makeMarriageProfileWithRecords(t, pool, 0, 0)

	status, body := callDelete(t, NewAdminDeleteHandler(pool).Marriage, f.profileID)

	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — an empty thread has no conversation to protect (body: %s)", status, body)
	}
	var stillThere bool
	if err := pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM marriage_profiles WHERE id = $1)`, f.profileID).Scan(&stillThere); err != nil {
		t.Fatalf("check profile: %v", err)
	}
	if stillThere {
		t.Error("the profile was not deleted")
	}
	if n := trashCountFor(t, pool, "marriage_profiles", f.profileID); n != 1 {
		t.Errorf("%d trash entries, want 1 — the delete must stay recoverable", n)
	}
}
