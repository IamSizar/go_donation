// stock_test.go — client report, 2026-09-22: "stock is 30, 12 are bought,
// stock stays 30 — it should update automatically with every purchase."
//
// Nothing anywhere ever wrote stock_quantity back down after CreateOrder's
// pre-purchase check, so the fix is migration 126's trigger, not Go code —
// this exercises it directly against a real Postgres, the same way
// catalogue_test.go does. See TEST_DATABASE_URL setup in that file's header.
package marketplace

import (
	"context"
	"testing"
)

func TestOrderCompletionDecrementsStockExactlyOnce(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()

	var productID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO marketplace_products (name, name_ar, category, price, currency, stock_quantity, status)
		VALUES ('Stock Test Widget', 'ويدجت اختبار المخزون', 'test', 5000, 'IQD', 30, 'approved')
		RETURNING id`,
	).Scan(&productID); err != nil {
		t.Fatalf("seed product: %v", err)
	}

	var orderID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO marketplace_orders (product_id, buyer_user_id, quantity, total_amount, currency, status)
		VALUES ($1, 1, 12, 60000, 'IQD', 'pending')
		RETURNING id`,
		productID,
	).Scan(&orderID); err != nil {
		t.Fatalf("seed order: %v", err)
	}

	stockOf := func() int {
		var stock int
		if err := pool.QueryRow(ctx,
			`SELECT stock_quantity FROM marketplace_products WHERE id = $1`, productID,
		).Scan(&stock); err != nil {
			t.Fatalf("read stock: %v", err)
		}
		return stock
	}

	setStatus := func(status string) {
		if _, err := pool.Exec(ctx,
			`UPDATE marketplace_orders SET status = $1 WHERE id = $2`, status, orderID,
		); err != nil {
			t.Fatalf("set status %s: %v", status, err)
		}
	}

	// Pending -> approved -> processing must not touch stock at all.
	for _, s := range []string{"approved", "processing"} {
		setStatus(s)
		if got := stockOf(); got != 30 {
			t.Fatalf("after -> %s: stock = %d, want unchanged 30", s, got)
		}
	}

	// The one transition that matters: -> completed decrements by quantity.
	setStatus("completed")
	if got := stockOf(); got != 18 {
		t.Fatalf("after -> completed: stock = %d, want 30-12=18", got)
	}

	// Re-saving the SAME status must be a no-op, not a second decrement —
	// this is what a naive `NEW.status = 'completed'` trigger (no OLD check)
	// would get wrong on every unrelated PATCH to an already-completed order.
	setStatus("completed")
	if got := stockOf(); got != 18 {
		t.Fatalf("after re-saving completed: stock = %d, want still 18 (no double decrement)", got)
	}

	// Moving away from completed (e.g. a cancellation recorded in error)
	// restocks the same quantity.
	setStatus("cancelled")
	if got := stockOf(); got != 30 {
		t.Fatalf("after completed -> cancelled: stock = %d, want restocked to 30", got)
	}
}

// A product with stock_quantity IS NULL is untracked/unlimited — CreateOrder's
// pre-purchase check already treats NULL that way, and the trigger must
// leave it NULL rather than trying arithmetic on it.
func TestOrderCompletionLeavesUntrackedStockAlone(t *testing.T) {
	pool := newTestPool(t)
	ctx := context.Background()

	var productID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO marketplace_products (name, name_ar, category, price, currency, stock_quantity, status)
		VALUES ('Untracked Stock Widget', 'ويدجت بدون تتبع', 'test', 5000, 'IQD', NULL, 'approved')
		RETURNING id`,
	).Scan(&productID); err != nil {
		t.Fatalf("seed product: %v", err)
	}

	var orderID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO marketplace_orders (product_id, buyer_user_id, quantity, total_amount, currency, status)
		VALUES ($1, 1, 5, 25000, 'IQD', 'pending')
		RETURNING id`,
		productID,
	).Scan(&orderID); err != nil {
		t.Fatalf("seed order: %v", err)
	}

	if _, err := pool.Exec(ctx,
		`UPDATE marketplace_orders SET status = 'completed' WHERE id = $1`, orderID,
	); err != nil {
		t.Fatalf("complete order: %v", err)
	}

	var stock *int
	if err := pool.QueryRow(ctx,
		`SELECT stock_quantity FROM marketplace_products WHERE id = $1`, productID,
	).Scan(&stock); err != nil {
		t.Fatalf("read stock: %v", err)
	}
	if stock != nil {
		t.Fatalf("stock_quantity = %d, want NULL (untracked) to stay NULL", *stock)
	}
}
