// marketplace_brand_test.go — K15: the product field that pretended to save.
//
// # WHY THIS FILE EXISTS
//
// `marketplace_products.brand` has existed since migration 100, the dashboard's
// product form has had a Brand input just as long, and the View page's column
// allow-list (admin_detail.go) even lists it. None of that mattered, because
// the value never reached the database and never came back out:
//
//   - productEditReq declared name/sku/specs/labels and NO brand, so the PATCH
//     unmarshalled the field into nothing and updated nothing.
//   - the create INSERT listed twenty columns and brand was not among them.
//   - neither SELECT in internal/marketplace mentioned it.
//
// So an admin could type a brand, press save, reopen the product, and find the
// box empty — with no error anywhere to explain it. That is worse than a
// missing feature: the form claimed to store something it discarded.
//
// These tests drive the REAL create and edit handlers and then read the row
// back through the REAL list query, because the bug lived in the gap between
// those three and any one of them tested alone would have looked fine.
//
// They need a throwaway Postgres and are skipped unless TEST_DATABASE_URL is
// set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_k15
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k15?sslmode=disable' \
//	  go test ./internal/handlers/ -run ProductBrand -v
package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/marketplace"
)

// ─── Harness ────────────────────────────────────────────────────────────

// createJSON drives a create handler through a real gin route, so the JSON
// unmarshalling is exercised exactly as production does it. The route's
// permission gate is deliberately absent: what is asserted here is the
// handler's effect on the database, and the gates are unchanged by this work.
func createJSON(t *testing.T, handler gin.HandlerFunc, body string) (int, string) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/x", handler)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/x", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

// patchJSON is createJSON for an edit handler: the route carries :id, because
// parseID reads it and a route without it would fail before the handler's own
// logic ran.
func patchJSON(t *testing.T, handler gin.HandlerFunc, id int64, body string) (int, string) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.PATCH("/x/:id", handler)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPatch, "/x/"+strconv.FormatInt(id, 10), strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

// productByID reads one product back through the store the dashboard's list
// actually uses, rather than a hand-written SELECT — the original bug was that
// the real query did not ask for the column, so a test that wrote its own
// SELECT would have passed while the dashboard stayed broken.
func productByID(t *testing.T, pool *pgxpool.Pool, id int64) marketplace.Product {
	t.Helper()
	res, err := marketplace.NewStore(pool).AdminListProducts(
		context.Background(), 1, 200, "", "k15-brand-")
	if err != nil {
		t.Fatalf("AdminListProducts: %v", err)
	}
	for _, p := range res.Items {
		if p.ID == id {
			return p
		}
	}
	t.Fatalf("product %d is not in the admin list of %d items", id, len(res.Items))
	return marketplace.Product{}
}

// ─── The round trip ─────────────────────────────────────────────────────

// Create with a brand, read it back. This is the create half of the gap.
func TestProductBrandSurvivesCreate(t *testing.T) {
	pool := newAuthTestPool(t)
	code, body := createJSON(t, NewAdminCreateHandler(pool, nil).MarketplaceProduct,
		`{"name":"k15-brand-create","brand":"Aurora","price":1000,"status":"approved"}`)
	if code != http.StatusOK {
		t.Fatalf("create returned %d: %s", code, body)
	}
	id := idFromCreateResponse(t, body)
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marketplace_products WHERE id = $1`, id)
	})

	if got := productByID(t, pool, id).Brand; got != "Aurora" {
		t.Errorf("brand = %q after creating the product with brand=Aurora, want %q "+
			"— the create INSERT does not carry the column", got, "Aurora")
	}
}

// Type a brand on an existing product, save, reopen. This is the exact
// sequence in the client's note, and the exact one that used to lose the value.
func TestProductBrandSurvivesEdit(t *testing.T) {
	pool := newAuthTestPool(t)
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO marketplace_products (name, price, currency, status)
		VALUES ('k15-brand-edit', 1000, 'IQD', 'approved') RETURNING id`,
	).Scan(&id); err != nil {
		t.Fatalf("insert fixture: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marketplace_products WHERE id = $1`, id)
	})

	code, body := patchJSON(t, NewAdminEditHandler(pool).MarketplaceProduct, id, `{"brand":"Aurora"}`)
	if code != http.StatusOK {
		t.Fatalf("patch returned %d: %s", code, body)
	}
	if got := productByID(t, pool, id).Brand; got != "Aurora" {
		t.Errorf("brand = %q after PATCH {\"brand\":\"Aurora\"}, want %q "+
			"— the edit struct does not declare the field", got, "Aurora")
	}

	// And it must be clearable. brand is NOT NULL DEFAULT '' in the schema, so
	// the generic "empty means NULL" helper the other text fields use would
	// have failed the constraint here rather than emptying the box.
	if code, body := patchJSON(t, NewAdminEditHandler(pool).MarketplaceProduct, id,
		`{"brand":""}`); code != http.StatusOK {
		t.Fatalf("clearing the brand returned %d: %s", code, body)
	}
	if got := productByID(t, pool, id).Brand; got != "" {
		t.Errorf("brand = %q after PATCH {\"brand\":\"\"}, want it cleared", got)
	}
}

// ─── The discount, same shape ───────────────────────────────────────────

// discount_percent is new (migration 109) and backs العروض والخصومات, so it
// gets the same round-trip proof rather than being assumed to work.
func TestProductDiscountRoundTripsAndValidates(t *testing.T) {
	pool := newAuthTestPool(t)
	code, body := createJSON(t, NewAdminCreateHandler(pool, nil).MarketplaceProduct,
		`{"name":"k15-brand-discount","price":1000,"discount_percent":25,"status":"approved"}`)
	if code != http.StatusOK {
		t.Fatalf("create returned %d: %s", code, body)
	}
	id := idFromCreateResponse(t, body)
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM marketplace_products WHERE id = $1`, id)
	})

	got := productByID(t, pool, id)
	if got.DiscountPercent == nil || *got.DiscountPercent != 25 {
		t.Fatalf("discount_percent = %v after create, want 25", got.DiscountPercent)
	}

	// 0 is how a discount is removed, and it must land as NULL — a stored 0
	// would put the product in the العروض feed advertising nothing.
	if code, body := patchJSON(t, NewAdminEditHandler(pool).MarketplaceProduct, id,
		`{"discount_percent":0}`); code != http.StatusOK {
		t.Fatalf("removing the discount returned %d: %s", code, body)
	}
	if p := productByID(t, pool, id); p.DiscountPercent != nil {
		t.Errorf("discount_percent = %v after setting it to 0, want nil (no discount)", p.DiscountPercent)
	}

	// An out-of-range value has to come back as a sentence, not as a
	// constraint-violation 500 with the raw Postgres error in it.
	code, body = patchJSON(t, NewAdminEditHandler(pool).MarketplaceProduct, id, `{"discount_percent":150}`)
	if code != http.StatusBadRequest {
		t.Errorf("PATCH discount_percent=150 returned %d: %s — want 400 with an explanation", code, body)
	}
	if strings.Contains(body, "SQLSTATE") || strings.Contains(body, "constraint") {
		t.Errorf("the rejection leaks the database error to the caller: %s", body)
	}
}

// idFromCreateResponse pulls the new row's id out of a create handler's
// {"success":true,"id":N} envelope.
func idFromCreateResponse(t *testing.T, body string) int64 {
	t.Helper()
	const key = `"id":`
	at := strings.Index(body, key)
	if at < 0 {
		t.Fatalf("create response has no id: %s", body)
	}
	rest := body[at+len(key):]
	end := strings.IndexAny(rest, ",}")
	if end < 0 {
		t.Fatalf("create response id is unterminated: %s", body)
	}
	id, err := strconv.ParseInt(strings.TrimSpace(rest[:end]), 10, 64)
	if err != nil {
		t.Fatalf("create response id %q is not a number: %v", rest[:end], err)
	}
	return id
}
