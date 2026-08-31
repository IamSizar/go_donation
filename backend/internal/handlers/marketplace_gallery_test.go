// marketplace_gallery_test.go — migration 117: a product's extra photos.
//
// # WHY THIS FILE EXISTS
//
// `marketplace_products.gallery` is a new column, and the failure mode a new
// column has in this codebase is not "it does not work" — it is "it works in
// three places out of four". `brand` is the proof: it existed in the schema and
// in the dashboard form for two releases while the PATCH silently dropped it,
// because no single test spanned the create handler, the edit handler and the
// SELECT the dashboard actually reads. See marketplace_brand_test.go.
//
// So these tests drive the REAL create and edit handlers and read the row back
// through the REAL queries — both of them: AdminListProducts, which populates
// the dashboard's edit form, and ListCatalogue, which is what the app receives.
// A gallery saved but not selected would pass a narrower test and still show
// the shopper nothing.
//
// The last test is the one that matters most in production: a product with NO
// gallery must come back as an empty list, never NULL, so the app's detail
// sheet draws exactly what it drew before this column existed.
//
// They need a throwaway Postgres and are skipped unless TEST_DATABASE_URL is
// set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_k15
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k15?sslmode=disable' \
//	  go test ./internal/handlers/ -run ProductGallery -v
package handlers

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/marketplace"
)

// galleryProductByID reads one product back through the store the DASHBOARD's
// product list uses — the query that populates the edit form. Named apart from
// productByID because that helper filters on the brand suite's own name prefix.
func galleryProductByID(t *testing.T, pool *pgxpool.Pool, id int64) marketplace.Product {
	t.Helper()
	res, err := marketplace.NewStore(pool).AdminListProducts(
		context.Background(), 1, 200, "", "m117-gallery-")
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

// galleryFromCatalogue reads the same product back through the PUBLIC query the
// app calls, which is a different SELECT in a different file. The gallery has
// to survive both or the dashboard and the app disagree about the product.
func galleryFromCatalogue(t *testing.T, pool *pgxpool.Pool, id int64) []string {
	t.Helper()
	page, err := marketplace.NewStore(pool).ListCatalogue(
		context.Background(), marketplace.ProductFilters{Limit: 100, Q: "m117-gallery-"})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	for _, p := range page.Items {
		if p.ID == id {
			return p.Gallery
		}
	}
	t.Fatalf("product %d is not in the public catalogue of %d items", id, len(page.Items))
	return nil
}

// deleteProduct removes the fixture however the test ends.
func deleteProduct(t *testing.T, pool *pgxpool.Pool, id int64) {
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(),
			`DELETE FROM marketplace_products WHERE id = $1`, id)
	})
}

// ─── Create ─────────────────────────────────────────────────────────────

// A gallery supplied on the create form must reach the database and come back
// out of both read paths, in the order it was given — the order is the order
// staff arranged the photos in, and a set-shaped round trip would lose it.
func TestProductGallerySurvivesCreate(t *testing.T) {
	pool := newAuthTestPool(t)
	code, body := createJSON(t, NewAdminCreateHandler(pool, nil).MarketplaceProduct,
		`{"name":"m117-gallery-create","price":1000,"status":"approved",`+
			`"image_path":"images/uploads/cover.jpg",`+
			`"gallery":["images/uploads/a.jpg","images/uploads/b.jpg"]}`)
	if code != http.StatusOK {
		t.Fatalf("create returned %d: %s", code, body)
	}
	id := idFromCreateResponse(t, body)
	deleteProduct(t, pool, id)

	got := galleryProductByID(t, pool, id)
	if len(got.Gallery) != 2 || got.Gallery[0] != "images/uploads/a.jpg" ||
		got.Gallery[1] != "images/uploads/b.jpg" {
		t.Errorf("gallery = %v after creating the product with two photos, "+
			"want them in order — the create INSERT does not carry the column", got.Gallery)
	}
	// The cover is a separate column and this change must not have disturbed
	// it: every existing screen still finds its thumbnail there.
	if got.ImagePath == nil || *got.ImagePath != "images/uploads/cover.jpg" {
		t.Errorf("image_path = %v, want the cover untouched by the gallery work", got.ImagePath)
	}
	if pub := galleryFromCatalogue(t, pool, id); len(pub) != 2 {
		t.Errorf("the public catalogue returned %v, want the 2 photos — "+
			"the app cannot show a gallery the catalogue query does not select", pub)
	}
}

// ─── Edit ───────────────────────────────────────────────────────────────

// Add photos to an existing product, reorder them, then clear them. This is the
// full sequence the dashboard's GalleryInput produces, and each step is a whole
// -array replace rather than an add/remove endpoint.
func TestProductGallerySurvivesEdit(t *testing.T) {
	pool := newAuthTestPool(t)
	var id int64
	if err := pool.QueryRow(context.Background(), `
		INSERT INTO marketplace_products (name, price, currency, status)
		VALUES ('m117-gallery-edit', 1000, 'IQD', 'approved') RETURNING id`,
	).Scan(&id); err != nil {
		t.Fatalf("insert fixture: %v", err)
	}
	deleteProduct(t, pool, id)

	// A product created before this column existed must start empty, not NULL.
	if got := galleryProductByID(t, pool, id).Gallery; len(got) != 0 {
		t.Fatalf("a fresh row has gallery = %v, want it empty", got)
	}

	edit := NewAdminEditHandler(pool).MarketplaceProduct
	if code, body := patchJSON(t, edit, id,
		`{"gallery":["images/uploads/a.jpg","images/uploads/b.jpg"]}`); code != http.StatusOK {
		t.Fatalf("adding photos returned %d: %s", code, body)
	}
	if got := galleryProductByID(t, pool, id).Gallery; len(got) != 2 {
		t.Fatalf("gallery = %v after the PATCH, want 2 photos "+
			"— the edit struct does not declare the field", got)
	}

	// Reordering is an ordinary save. If the column were a set, or the handler
	// sorted or de-duplicated, this is where it would show.
	if code, body := patchJSON(t, edit, id,
		`{"gallery":["images/uploads/b.jpg","images/uploads/a.jpg"]}`); code != http.StatusOK {
		t.Fatalf("reordering returned %d: %s", code, body)
	}
	if got := galleryProductByID(t, pool, id).Gallery; len(got) != 2 ||
		got[0] != "images/uploads/b.jpg" {
		t.Errorf("gallery = %v after reordering, want b before a", got)
	}

	// An explicit empty array is how staff remove every photo. It must clear
	// the column rather than be mistaken for "the request said nothing".
	if code, body := patchJSON(t, edit, id, `{"gallery":[]}`); code != http.StatusOK {
		t.Fatalf("clearing the gallery returned %d: %s", code, body)
	}
	if got := galleryProductByID(t, pool, id).Gallery; len(got) != 0 {
		t.Errorf("gallery = %v after PATCH {\"gallery\":[]}, want it cleared", got)
	}
}

// A PATCH that does not mention the gallery must leave it alone. The dashboard
// sends only the fields that changed, so a nil-means-empty reading here would
// wipe a product's photos every time someone corrected its price.
func TestProductGalleryUntouchedByAnUnrelatedEdit(t *testing.T) {
	pool := newAuthTestPool(t)
	code, body := createJSON(t, NewAdminCreateHandler(pool, nil).MarketplaceProduct,
		`{"name":"m117-gallery-keep","price":1000,"status":"approved",`+
			`"gallery":["images/uploads/a.jpg"]}`)
	if code != http.StatusOK {
		t.Fatalf("create returned %d: %s", code, body)
	}
	id := idFromCreateResponse(t, body)
	deleteProduct(t, pool, id)

	if code, body := patchJSON(t, NewAdminEditHandler(pool).MarketplaceProduct, id,
		`{"price":2000}`); code != http.StatusOK {
		t.Fatalf("editing the price returned %d: %s", code, body)
	}
	if got := galleryProductByID(t, pool, id).Gallery; len(got) != 1 {
		t.Errorf("gallery = %v after an unrelated price edit, want the photo kept", got)
	}
}

// ─── The common case ────────────────────────────────────────────────────

// Almost every product has no gallery, and that case must be indistinguishable
// from how the shop behaved before this column existed: an empty list on both
// read paths, and `"gallery":[]` — never `null` — in the JSON the app parses.
func TestProductWithoutGalleryIsEmptyNeverNull(t *testing.T) {
	pool := newAuthTestPool(t)
	code, body := createJSON(t, NewAdminCreateHandler(pool, nil).MarketplaceProduct,
		`{"name":"m117-gallery-none","price":1000,"status":"approved"}`)
	if code != http.StatusOK {
		t.Fatalf("create returned %d: %s", code, body)
	}
	id := idFromCreateResponse(t, body)
	deleteProduct(t, pool, id)

	got := galleryProductByID(t, pool, id)
	if got.Gallery == nil {
		t.Errorf("gallery is nil for a product created without one; it must be " +
			"an empty slice so it serialises as [] rather than null")
	}
	if len(got.Gallery) != 0 {
		t.Errorf("gallery = %v for a product created without one, want it empty", got.Gallery)
	}
	if pub := galleryFromCatalogue(t, pool, id); pub == nil || len(pub) != 0 {
		t.Errorf("the public catalogue returned %v, want an empty gallery", pub)
	}

	// And the whole point: nothing about such a product changed. Reading the
	// row is still one query with no join, and the cover is still where every
	// existing screen looks for it.
	if got.ImagePath != nil {
		t.Errorf("image_path = %v, want nil for a product created without a cover", got.ImagePath)
	}
}

// ─── Input hygiene ──────────────────────────────────────────────────────

// Blank entries must never be stored. A path that trims to nothing resolves to
// nothing, so it would render as a broken tile in the middle of the strip.
func TestProductGalleryDropsBlankEntries(t *testing.T) {
	pool := newAuthTestPool(t)
	code, body := createJSON(t, NewAdminCreateHandler(pool, nil).MarketplaceProduct,
		`{"name":"m117-gallery-blanks","price":1000,"status":"approved",`+
			`"gallery":["  ","images/uploads/a.jpg",""]}`)
	if code != http.StatusOK {
		t.Fatalf("create returned %d: %s", code, body)
	}
	id := idFromCreateResponse(t, body)
	deleteProduct(t, pool, id)

	if got := galleryProductByID(t, pool, id).Gallery; len(got) != 1 ||
		strings.TrimSpace(got[0]) == "" {
		t.Errorf("gallery = %v, want only the one real path — blanks must be dropped", got)
	}
}
