// pending_counts_marketplace_test.go — the marketplace sidebar badge must be
// monotonic: it counts orders that are still waiting for a staff decision, and
// acting on an order can only ever make it smaller.
//
// Client feedback round 1: the badge counted status IN ('pending','processing').
// marketplace_orders' lifecycle is pending → approved → processing → completed
// (migrations/001_full_v2.sql:449, handlers/admin_status.go), so approving an
// order DROPPED the badge and the later move to 'processing' BROUGHT IT BACK —
// staff saw work reappear that they had already actioned.
//
// Only 'pending' is "awaiting staff action". Note these are deliberately NOT
// unread counts: there is no per-section last_seen_at and none is wanted,
// because a record nobody has actioned must keep showing.
//
// Integration test against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set:
//
//	TEST_DATABASE_URL='postgres://localhost:5432/tfix1?sslmode=disable' \
//	  go test ./internal/handlers/ -run MarketplacePendingBadge -count=1
package handlers

import (
	"context"
	"fmt"
	"math/rand"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// marketplaceBadge reads the live marketplace count out of the handler.
func marketplaceBadge(t *testing.T, pool *pgxpool.Pool) int {
	t.Helper()
	h := &PendingCountsHandler{Pool: pool}
	body := callAsStaff(t, h.Counts, "")
	n, ok := body["marketplace"].(float64)
	if !ok {
		t.Fatalf("no marketplace count in response: %v", body)
	}
	return int(n)
}

// seedMarketplaceOrder inserts one order in the given status and returns its id.
// It creates its own product so the row is self-contained.
func seedMarketplaceOrder(t *testing.T, pool *pgxpool.Pool, status string) int64 {
	t.Helper()
	ctx := context.Background()
	var productID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marketplace_products (name, price) VALUES ($1, 1000) RETURNING id`,
		fmt.Sprintf("badge-product-%d", rand.Intn(100000000)),
	).Scan(&productID); err != nil {
		t.Fatalf("insert product: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marketplace_products WHERE id = $1`, productID)
	})
	var orderID int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO marketplace_orders (product_id, quantity, status) VALUES ($1, 1, $2) RETURNING id`,
		productID, status,
	).Scan(&orderID); err != nil {
		t.Fatalf("insert order (%s): %v", status, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marketplace_orders WHERE id = $1`, orderID)
	})
	return orderID
}

// TestMarketplacePendingBadgeCountsOnlyPendingOrders pins the whole rule in one
// pass: a pending order adds exactly 1, and none of the three post-decision
// statuses adds anything.
func TestMarketplacePendingBadgeCountsOnlyPendingOrders(t *testing.T) {
	pool := newDupProfilesPool(t)
	before := marketplaceBadge(t, pool)

	seedMarketplaceOrder(t, pool, "pending")
	if got, want := marketplaceBadge(t, pool), before+1; got != want {
		t.Fatalf("after one pending order badge = %d, want %d", got, want)
	}

	// Each of these is a decision staff already made. None may re-raise the badge.
	for _, status := range []string{"approved", "processing", "completed"} {
		seedMarketplaceOrder(t, pool, status)
		if got, want := marketplaceBadge(t, pool), before+1; got != want {
			t.Errorf("a %q order changed the badge: got %d, want %d — only 'pending' awaits staff action",
				status, got, want)
		}
	}
}

// TestMarketplacePendingBadgeIsMonotonicAcrossTheLifecycle is the reported
// symptom itself: walking one order through its real lifecycle must never make
// the badge go back up.
func TestMarketplacePendingBadgeIsMonotonicAcrossTheLifecycle(t *testing.T) {
	pool := newDupProfilesPool(t)
	baseline := marketplaceBadge(t, pool)
	orderID := seedMarketplaceOrder(t, pool, "pending")

	previous := marketplaceBadge(t, pool)
	if previous != baseline+1 {
		t.Fatalf("a new pending order did not raise the badge: %d → %d", baseline, previous)
	}
	for _, status := range []string{"approved", "processing", "completed"} {
		if _, err := pool.Exec(context.Background(),
			`UPDATE marketplace_orders SET status = $1 WHERE id = $2`, status, orderID); err != nil {
			t.Fatalf("move order to %s: %v", status, err)
		}
		got := marketplaceBadge(t, pool)
		if got > previous {
			t.Errorf("moving the order to %q raised the badge from %d to %d — staff see actioned work return",
				status, previous, got)
		}
		previous = got
	}
	if previous != baseline {
		t.Errorf("a fully completed order still counts: badge %d, want the %d it started at", previous, baseline)
	}
}
