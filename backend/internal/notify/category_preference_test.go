// K7 — "choose which kinds of alerts you get" had no server-side answer.
//
// THE SHAPE OF THE GAP
// users.notifications_enabled (migration 039) was a single SMALLINT and the
// ONLY notification preference in the schema: all alerts or none. There was no
// per-type table, column or endpoint anywhere in the backend.
//
// A client-side filter was considered on the app side and rejected, correctly:
// the push is composed and sent HERE, so a switch living in the app would
// silence the in-app list while the phone still lit up. These tests are what
// makes the switch real — they drive the actual Send path with a category
// switched off and assert that nothing is written and nothing is queued.
//
// They need a throwaway Postgres and are skipped unless TEST_DATABASE_URL is
// set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_k7          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k7?sslmode=disable' \
//	  go test ./internal/notify/ -run Category -v
package notify

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// ─── Harness ────────────────────────────────────────────────────────────

func newCategoryTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping notification-category integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

var (
	catSeq    int64
	catRunTag = time.Now().UnixNano() % 100000
)

func makeNotifyUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	catSeq++
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO users (phone, role_id, active, registration_status)
		 VALUES ($1, 1, 1, 'approved') RETURNING id`,
		fmt.Sprintf("96477%05d%04d", catRunTag, catSeq),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM app_notifications WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM notification_preferences WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id
}

// disableCategory writes the preference exactly as the endpoint would.
func disableCategory(t *testing.T, pool *pgxpool.Pool, userID int64, category string) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`INSERT INTO notification_preferences (user_id, category, enabled) VALUES ($1, $2, FALSE)
		 ON CONFLICT (user_id, category) DO UPDATE SET enabled = FALSE`,
		userID, category); err != nil {
		t.Fatalf("disable category: %v", err)
	}
}

func countNotifications(t *testing.T, pool *pgxpool.Pool, userID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM app_notifications WHERE user_id = $1`, userID).Scan(&n); err != nil {
		t.Fatalf("count notifications: %v", err)
	}
	return n
}

// msg builds a distinct message so the dedupe check inside Send can never be
// what makes a test pass.
func msg(kind, tag string) LocalizedMessage {
	return LocalizedMessage{
		Title: LocalText{En: "Title " + tag},
		Body:  LocalText{En: "Body " + tag},
		Type:  kind,
	}
}

// ─── Tests ──────────────────────────────────────────────────────────────

// The row the client asked for: switch off one kind of alert and keep the
// rest. resolveCategory maps *_donation_* to "payment" and *_reminder to
// "reminder", so these two messages land in different categories.
func TestCategoryOffSuppressesOnlyThatCategory(t *testing.T) {
	pool := newCategoryTestPool(t)
	ctx := context.Background()
	n := New(pool)
	uid := makeNotifyUser(t, pool)

	disableCategory(t, pool, uid, "payment")

	if _, err := n.Send(ctx, uid, msg("donation_received", "pay1")); err != nil {
		t.Fatalf("Send(payment): %v", err)
	}
	if got := countNotifications(t, pool, uid); got != 0 {
		t.Fatalf("a 'payment' alert was stored (%d rows) after the user switched that category off", got)
	}

	if _, err := n.Send(ctx, uid, msg("sponsorship_payment_due_reminder", "rem1")); err != nil {
		t.Fatalf("Send(reminder): %v", err)
	}
	if got := countNotifications(t, pool, uid); got != 1 {
		t.Fatalf("notifications = %d, want 1 — only 'payment' was switched off, 'reminder' must still arrive", got)
	}
}

// A user who has never opened the screen must keep receiving everything.
// Absence of a row means enabled; a default of "off" would silently mute the
// entire existing user base the moment this migration ran.
func TestNoPreferenceRowMeansEverythingStillArrives(t *testing.T) {
	pool := newCategoryTestPool(t)
	ctx := context.Background()
	n := New(pool)
	uid := makeNotifyUser(t, pool)

	for i, m := range []LocalizedMessage{
		msg("donation_received", "d1"),
		msg("case_urgent_update", "u1"),
		msg("new_campaign", "c1"),
	} {
		if _, err := n.Send(ctx, uid, m); err != nil {
			t.Fatalf("Send #%d: %v", i, err)
		}
	}
	if got := countNotifications(t, pool, uid); got != 3 {
		t.Fatalf("notifications = %d, want 3 — a user with no saved preference must receive everything", got)
	}
}

// Re-enabling must actually re-enable: the row flips rather than being a
// one-way mute.
func TestCategoryCanBeSwitchedBackOn(t *testing.T) {
	pool := newCategoryTestPool(t)
	ctx := context.Background()
	n := New(pool)
	uid := makeNotifyUser(t, pool)

	disableCategory(t, pool, uid, "campaign")
	if _, err := n.Send(ctx, uid, msg("new_campaign", "c1")); err != nil {
		t.Fatalf("Send: %v", err)
	}
	if got := countNotifications(t, pool, uid); got != 0 {
		t.Fatalf("a 'campaign' alert arrived (%d rows) while that category was off", got)
	}

	if _, err := pool.Exec(ctx,
		`UPDATE notification_preferences SET enabled = TRUE WHERE user_id = $1 AND category = 'campaign'`,
		uid); err != nil {
		t.Fatalf("re-enable: %v", err)
	}
	if _, err := n.Send(ctx, uid, msg("new_campaign", "c2")); err != nil {
		t.Fatalf("Send after re-enable: %v", err)
	}
	if got := countNotifications(t, pool, uid); got != 1 {
		t.Fatalf("notifications = %d, want 1 — the category was switched back on", got)
	}
}

// The master switch still wins: turning everything off must not be undone by
// a per-category row that happens to say enabled.
func TestMasterSwitchStillOverridesTheCategorySwitches(t *testing.T) {
	pool := newCategoryTestPool(t)
	ctx := context.Background()
	n := New(pool)
	uid := makeNotifyUser(t, pool)

	if _, err := pool.Exec(ctx, `UPDATE users SET notifications_enabled = 0 WHERE id = $1`, uid); err != nil {
		t.Fatalf("disable master switch: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO notification_preferences (user_id, category, enabled) VALUES ($1, 'payment', TRUE)`,
		uid); err != nil {
		t.Fatalf("enable category: %v", err)
	}
	if _, err := n.Send(ctx, uid, msg("donation_received", "m1")); err != nil {
		t.Fatalf("Send: %v", err)
	}
	if got := countNotifications(t, pool, uid); got != 0 {
		t.Fatalf("notifications = %d, want 0 — the master switch is off", got)
	}
}

// The catalogue is what the Settings screen renders, so the migration's seed
// is part of the contract — including the label keys, which must be ones the
// app already has in all four locales rather than new vocabulary.
func TestNotificationCategoryCatalogueIsSeeded(t *testing.T) {
	pool := newCategoryTestPool(t)
	rows, err := pool.Query(context.Background(),
		`SELECT category, label_key FROM notification_categories WHERE enabled = true`)
	if err != nil {
		t.Fatalf("read catalogue: %v", err)
	}
	defer rows.Close()
	got := map[string]string{}
	for rows.Next() {
		var c, l string
		if err := rows.Scan(&c, &l); err != nil {
			t.Fatalf("scan: %v", err)
		}
		got[c] = l
	}
	// Every category resolveCategory can return needs a switch, or that kind
	// of alert would be unswitchable.
	want := map[string]string{
		"urgent": "Urgent", "payment": "Payment", "campaign": "Campaign",
		"system": "System", "reminder": "Reminder", "normal": "Normal",
	}
	for cat, label := range want {
		if got[cat] == "" {
			t.Errorf("catalogue is missing %q — resolveCategory can return it, so it must be switchable", cat)
			continue
		}
		if got[cat] != label {
			t.Errorf("category %q has label_key %q, want the app's existing key %q", cat, got[cat], label)
		}
	}
}

// Every category the catalogue offers must be one resolveCategory can actually
// produce, or the screen would show a switch that governs nothing.
func TestEveryCatalogueCategoryIsReachable(t *testing.T) {
	pool := newCategoryTestPool(t)
	rows, err := pool.Query(context.Background(),
		`SELECT category FROM notification_categories WHERE enabled = true`)
	if err != nil {
		t.Fatalf("read catalogue: %v", err)
	}
	defer rows.Close()
	reachable := map[string]bool{}
	for _, sample := range []string{
		"case_urgent_update", "donation_received", "new_campaign",
		"system_test", "sponsorship_payment_due_reminder", "something_else",
	} {
		reachable[resolveCategory(sample)] = true
	}
	for rows.Next() {
		var cat string
		if err := rows.Scan(&cat); err != nil {
			t.Fatalf("scan: %v", err)
		}
		if !reachable[cat] {
			t.Errorf("catalogue offers %q, which resolveCategory never returns — that switch would govern nothing", cat)
		}
	}
}
