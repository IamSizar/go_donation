// R2 #66 — a store order records how the buyer chose to pay, like a donation
// does, and returns it in the buyer's list and the staff list.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set.
package marketplace

import (
	"context"
	"strings"
	"testing"
)

func TestOrderRecordsThePaymentMethodChosen(t *testing.T) {
	pool := newTestPool(t)
	s := &Store{Pool: pool}
	ctx := context.Background()

	var productID int64
	if err := pool.QueryRow(ctx, `
		INSERT INTO marketplace_products (name, category, price, currency, stock_quantity, status)
		VALUES ('Payment Method Widget', 'test', 4000, 'IQD', 10, 'approved') RETURNING id`,
	).Scan(&productID); err != nil {
		t.Fatalf("seed product: %v", err)
	}
	var buyer int64
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active) VALUES ('96470099001', 1, 1) RETURNING id`).Scan(&buyer); err != nil {
		t.Fatalf("seed buyer: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM marketplace_orders WHERE product_id = $1`, productID)
		_, _ = pool.Exec(ctx, `DELETE FROM marketplace_products WHERE id = $1`, productID)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, buyer)
	})

	id, _, _, err := s.CreateOrder(ctx, buyer, productID, 2, "", "  FIB  ")
	if err != nil || id == 0 {
		t.Fatalf("CreateOrder: id=%d err=%v", id, err)
	}
	// A method name is stored trimmed, and capped.
	long := strings.Repeat("x", 100)
	id2, _, _, err := s.CreateOrder(ctx, buyer, productID, 1, "", long)
	if err != nil || id2 == 0 {
		t.Fatalf("CreateOrder long: id=%d err=%v", id2, err)
	}

	got := map[int64]string{}
	items, err := s.ListOrdersForUser(ctx, buyer, 1, 20)
	if err != nil {
		t.Fatalf("ListOrdersForUser: %v", err)
	}
	for _, o := range items {
		got[o.ID] = o.PaymentMethod
	}
	if got[id] != "FIB" {
		t.Fatalf("payment_method = %q, want FIB", got[id])
	}
	if len([]rune(got[id2])) != 64 {
		t.Fatalf("long payment_method stored with %d chars, want 64", len([]rune(got[id2])))
	}
}
