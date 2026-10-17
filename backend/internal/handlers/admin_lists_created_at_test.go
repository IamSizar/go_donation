// admin_lists_created_at_test.go — the dashboard's campaigns, receipts and
// partners lists carry a created_at so each can show a date/time column
// (client item #74). Integration test, skipped unless TEST_DATABASE_URL is set:
//
//	TEST_DATABASE_URL='postgres://localhost/r2test?sslmode=disable' \
//	  go test ./internal/handlers/ -run ListsCarryCreatedAt -count=1
package handlers

import (
	"context"
	"fmt"
	"math/rand"
	"testing"

	"github.com/karam-flutter/humanitarian-backend/internal/listings"
)

func firstItem(t *testing.T, body map[string]any, what string) map[string]any {
	t.Helper()
	items, _ := body["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("%s: got %d items, want 1", what, len(items))
	}
	it, _ := items[0].(map[string]any)
	return it
}

func TestCampaignsListCarriesCreatedAt(t *testing.T) {
	pool := newDupProfilesPool(t)
	ctx := context.Background()
	mk := func(label string, nullDate bool) (int64, string) {
		title := fmt.Sprintf("created-at-%s-%d", label, rand.Intn(1000000))
		var id int64
		if err := pool.QueryRow(ctx,
			`INSERT INTO campaigns (title, title_ar, description, description_ar,
			                        address, beneficiaries, goal_amount, raised_amount)
			 VALUES ($1, $1, 'seed', 'seed', 'Erbil', 10, 1000, 0) RETURNING id`, title,
		).Scan(&id); err != nil {
			t.Fatalf("insert campaign: %v", err)
		}
		if nullDate {
			// A campaign that predates migration 141.
			if _, err := pool.Exec(ctx, `UPDATE campaigns SET created_at = NULL WHERE id = $1`, id); err != nil {
				t.Fatalf("null created_at: %v", err)
			}
		}
		t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM campaigns WHERE id = $1`, id) })
		return id, title
	}
	_, fresh := mk("fresh", false)
	_, old := mk("old", true)

	h := &AdminListsHandler{Pool: pool}
	if v := firstItem(t, callAsStaff(t, h.Campaigns, "q="+fresh), "fresh campaign")["created_at"]; v == nil || v == "" {
		t.Errorf("a new campaign must be stamped, got created_at=%v", v)
	}
	// NULL must come through as JSON null, not break the scan.
	if v := firstItem(t, callAsStaff(t, h.Campaigns, "q="+old), "old campaign")["created_at"]; v != nil {
		t.Errorf("a pre-migration campaign must report null, got %v", v)
	}
}

func TestReceiptsListCarriesCreatedAt(t *testing.T) {
	pool := newDupProfilesPool(t)
	code := fmt.Sprintf("RCP-TEST-%d", rand.Intn(1000000))
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO aid_receipts (receipt_code, items) VALUES ($1, 'x') RETURNING id`, code,
	).Scan(&id); err != nil {
		t.Fatalf("insert receipt: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM aid_receipts WHERE id = $1`, id) })

	h := &AidReceiptsHandler{Pool: pool}
	body := callAsStaff(t, h.AdminList, "")
	items, _ := body["items"].([]any)
	for _, raw := range items {
		it, _ := raw.(map[string]any)
		if it["receipt_code"] == code {
			if it["created_at"] == nil || it["created_at"] == "" {
				t.Fatalf("receipt must carry created_at, got %v", it["created_at"])
			}
			return
		}
	}
	t.Fatalf("receipt %s missing from the list", code)
}

func TestPartnersListCarriesCreatedAt(t *testing.T) {
	pool := newDupProfilesPool(t)
	name := fmt.Sprintf("created-at-partner-%d", rand.Intn(1000000))
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO partners (name, status) VALUES ($1, 'active') RETURNING id`, name,
	).Scan(&id); err != nil {
		t.Fatalf("insert partner: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM partners WHERE id = $1`, id) })

	items, err := listings.New(pool).ListPartners(context.Background(), "", name, 10, 0)
	if err != nil || len(items) != 1 {
		t.Fatalf("ListPartners: %d items, err=%v", len(items), err)
	}
	if items[0].CreatedAt == nil || *items[0].CreatedAt == "" {
		t.Fatalf("partner must carry created_at, got %v", items[0].CreatedAt)
	}
}
