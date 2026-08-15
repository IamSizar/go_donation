// catalogue_test.go — K15: the six functional labels the product list promised.
//
// # WHY THIS FILE EXISTS
//
// The client's product-list spec names six labels: الأكثر مبيعاً, وصل حديثاً,
// العروض والخصومات, التصفية, الفئات, العلامات التجارية. None of them worked,
// and none of them COULD, because the only public query was
//
//	ListProducts(ctx, page, limit) ... ORDER BY id DESC
//
// which took no filter, no sort, and did not even SELECT created_at. Chips
// built on top of that could have re-sorted the twenty rows already in hand —
// so "الأكثر مبيعاً" would have described one page rather than the catalogue.
//
// Every test below therefore asserts the same structural property in a
// different dress: THE ANSWER IS COMPUTED OVER THE WHOLE CATALOGUE, NOT OVER A
// PAGE. Each one seeds more products than fit in the page it asks for, and
// checks that the right rows are on page 1. A page-local implementation passes
// none of them.
//
// These need a throwaway Postgres and are skipped unless TEST_DATABASE_URL is
// set, so `go test ./...` stays green on a bare checkout (same convention as
// internal/marriage/field_privacy_test.go):
//
//	createdb godonation_k15        # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k15?sslmode=disable' \
//	  go test ./internal/marketplace/ -v
package marketplace

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/db"
)

// ─── Harness ────────────────────────────────────────────────────────────

func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping marketplace catalogue integration test")
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

// runTag keeps two runs against the same database apart, so a run that dies
// before its cleanup cannot make the next one collide.
var runTag = time.Now().UnixNano() % 100000

// seed describes one fixture product. Zero values mean "leave it out", which
// is what an ordinary product in the catalogue looks like.
type seed struct {
	name         string
	category     string
	brand        string
	price        float64
	stock        *int
	status       string // "" → approved
	discount     *int
	labels       []string
	createdOffet time.Duration // relative to now; negative = older
	sold         int           // quantity across completed orders
}

func intPtr(n int) *int { return &n }

// makeProducts inserts the fixtures and removes them (and their orders)
// afterwards, so a test never depends on — or disturbs — whatever else is in
// the table. Returns the ids in the order given.
func makeProducts(t *testing.T, pool *pgxpool.Pool, seeds ...seed) []int64 {
	t.Helper()
	ctx := context.Background()
	ids := make([]int64, 0, len(seeds))
	for i, s := range seeds {
		status := s.status
		if status == "" {
			status = "approved"
		}
		labels := s.labels
		if labels == nil {
			labels = []string{}
		}
		var id int64
		if err := pool.QueryRow(ctx, `
			INSERT INTO marketplace_products
			   (name, category_slug, brand, price, currency, stock_quantity, status,
			    discount_percent, labels, created_at)
			VALUES ($1, $2, $3, $4, 'IQD', $5, $6, $7, $8, CURRENT_TIMESTAMP + $9::interval)
			RETURNING id`,
			s.name, nullIfEmpty(s.category), s.brand, s.price, s.stock, status,
			s.discount, labels, s.createdOffet.String(),
		).Scan(&id); err != nil {
			t.Fatalf("insert fixture product %d (%s): %v", i, s.name, err)
		}
		t.Cleanup(func() {
			_, _ = pool.Exec(context.Background(), `DELETE FROM marketplace_orders WHERE product_id = $1`, id)
			_, _ = pool.Exec(context.Background(), `DELETE FROM marketplace_products WHERE id = $1`, id)
		})
		if s.sold > 0 {
			if _, err := pool.Exec(ctx, `
				INSERT INTO marketplace_orders (product_id, quantity, total_amount, currency, status)
				VALUES ($1, $2, $3, 'IQD', 'completed')`,
				id, s.sold, s.price*float64(s.sold),
			); err != nil {
				t.Fatalf("insert fixture order for product %d: %v", id, err)
			}
		}
		ids = append(ids, id)
	}
	return ids
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// rank reports where a product id appears in a result page, or -1.
func rank(items []CatalogueProduct, id int64) int {
	for i, p := range items {
		if p.ID == id {
			return i
		}
	}
	return -1
}

func has(items []CatalogueProduct, id int64) bool { return rank(items, id) >= 0 }

// ─── وصل حديثاً — newest, over the whole catalogue ──────────────────────

// The fixtures are inserted OLDEST FIRST, so their ids ascend while their
// created_at descends. `ORDER BY id DESC` — the only ordering that existed —
// would return them in exactly the wrong order, which is what makes this test
// tell the two implementations apart.
func TestCatalogueNewestSortsByCreatedAtNotByID(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-new-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-oldest", createdOffet: -72 * time.Hour},
		seed{name: tag + "-middle", createdOffet: -48 * time.Hour},
		seed{name: tag + "-newest", createdOffet: -1 * time.Hour},
	)

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, Sort: SortNewest, Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	if len(page.Items) != 3 {
		t.Fatalf("got %d items, want the 3 fixtures", len(page.Items))
	}
	if page.Items[0].ID != ids[2] || page.Items[2].ID != ids[0] {
		t.Errorf("newest-first order is wrong: got ids %d,%d,%d — want %d (newest) first and %d (oldest) last",
			page.Items[0].ID, page.Items[1].ID, page.Items[2].ID, ids[2], ids[0])
	}
	// created_at was not even SELECTed before, so a zero here means the column
	// never made it into the response the app has to render "وصل حديثاً" from.
	if page.Items[0].CreatedAt.IsZero() {
		t.Errorf("created_at is zero — the app cannot show a new-arrival date it was never sent")
	}
}

// The page-local trap, made explicit: ask for ONE row and the newest product
// in the catalogue must be it, not the newest of some other page.
func TestCatalogueNewestIsNotJustTheCurrentPageResorted(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-page-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-a", createdOffet: -72 * time.Hour},
		seed{name: tag + "-b", createdOffet: -48 * time.Hour},
		seed{name: tag + "-c", createdOffet: -1 * time.Hour},
	)

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, Sort: SortNewest, Limit: 1, Page: 1,
	})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].ID != ids[2] {
		t.Fatalf("page 1 of size 1 = %v, want only the newest product %d", page.Items, ids[2])
	}
	if page.TotalItems != 3 {
		t.Errorf("total_items = %d, want 3 — the app cannot page a catalogue whose size it is never told",
			page.TotalItems)
	}
	if !page.HasMore {
		t.Errorf("has_more = false on page 1 of 3 items at 1 per page")
	}
}

// ─── الأكثر مبيعاً — best selling ───────────────────────────────────────

// Ids ascend with sales DESCENDING, so `ORDER BY id DESC` produces the exact
// opposite of the right answer.
func TestCatalogueBestSellingRanksByOrderedQuantity(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-sold-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-hit", price: 1000, sold: 40},
		seed{name: tag + "-mid", price: 1000, sold: 7},
		seed{name: tag + "-none", price: 1000},
	)

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, Sort: SortBestSelling, Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	if len(page.Items) != 3 {
		t.Fatalf("got %d items, want the 3 fixtures", len(page.Items))
	}
	if page.Items[0].ID != ids[0] || page.Items[2].ID != ids[2] {
		t.Errorf("best-selling order is wrong: got %d,%d,%d — want %d (40 sold) first and %d (0 sold) last",
			page.Items[0].ID, page.Items[1].ID, page.Items[2].ID, ids[0], ids[2])
	}
	if page.Items[0].SoldCount != 40 {
		t.Errorf("sold_count = %d for the best seller, want 40 — a chip claiming "+
			"'best selling' has to be able to show what it counted", page.Items[0].SoldCount)
	}
}

// A cancelled order is not a sale. Without this, "الأكثر مبيعاً" would rank a
// product nobody actually bought above one people did.
func TestCatalogueBestSellingIgnoresCancelledOrders(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-cancel-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-real", price: 500, sold: 3},
		seed{name: tag + "-ghost", price: 500},
	)
	if _, err := pool.Exec(context.Background(), `
		INSERT INTO marketplace_orders (product_id, quantity, total_amount, currency, status)
		VALUES ($1, 99, 49500, 'IQD', 'cancelled')`, ids[1]); err != nil {
		t.Fatalf("insert cancelled order: %v", err)
	}

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, Sort: SortBestSelling, Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	if page.Items[0].ID != ids[0] {
		t.Errorf("a product with 99 CANCELLED units outranked one with 3 real sales")
	}
	if got := page.Items[rank(page.Items, ids[1])].SoldCount; got != 0 {
		t.Errorf("sold_count = %d for a product whose only order was cancelled, want 0", got)
	}
}

// ─── العروض والخصومات — offers and discounts ────────────────────────────

func TestCatalogueOffersFilterFindsDiscountsAndSaleBadges(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-offer-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-percent", price: 1000, discount: intPtr(25)},
		seed{name: tag + "-badge", price: 1000, labels: []string{"sale"}},
		seed{name: tag + "-plain", price: 1000},
	)

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, OnSale: true, Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	if !has(page.Items, ids[0]) {
		t.Errorf("a product with discount_percent=25 is missing from the offers feed")
	}
	// Staff have been tagging products 'sale' since migration 036. If the
	// offers feed only understood the new column, every one of those would
	// vanish from the feed the day it shipped.
	if !has(page.Items, ids[1]) {
		t.Errorf("a product labelled 'sale' is missing from the offers feed")
	}
	if has(page.Items, ids[2]) {
		t.Errorf("an undiscounted, unlabelled product is in the offers feed")
	}
	if page.TotalItems != 2 {
		t.Errorf("total_items = %d for the offers feed, want 2", page.TotalItems)
	}
}

// The discounted price is computed once, on the server, so four clients cannot
// round it four ways.
func TestCatalogueReportsThePriceAfterDiscount(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-price-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-off", price: 1000, discount: intPtr(25)},
		seed{name: tag + "-full", price: 1000},
	)

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{Q: tag, Limit: 10})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	discounted := page.Items[rank(page.Items, ids[0])]
	if discounted.DiscountPercent == nil || *discounted.DiscountPercent != 25 {
		t.Fatalf("discount_percent = %v, want 25", discounted.DiscountPercent)
	}
	if discounted.PriceAfterDiscount != "750.00" {
		t.Errorf("price_after_discount = %q for 1000 at 25%% off, want \"750.00\"",
			discounted.PriceAfterDiscount)
	}
	// An undiscounted product must still answer the question, so the app has
	// one field to print rather than a branch to get wrong.
	full := page.Items[rank(page.Items, ids[1])]
	if full.PriceAfterDiscount != "1000.00" {
		t.Errorf("price_after_discount = %q for an undiscounted product, want the full price",
			full.PriceAfterDiscount)
	}
}

// ─── الفئات / العلامات التجارية — category and brand filters ────────────

func TestCatalogueFiltersByCategoryAndBrand(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-filter-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-a", category: "electronics_appliances", brand: "Aurora", price: 100},
		seed{name: tag + "-b", category: "electronics_appliances", brand: "Beko", price: 100},
		seed{name: tag + "-c", category: "fashion_clothing", brand: "Aurora", price: 100},
	)

	byCategory, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, CategorySlug: "electronics_appliances", Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue(category): %v", err)
	}
	if len(byCategory.Items) != 2 || has(byCategory.Items, ids[2]) {
		t.Errorf("category filter returned %d items and %v for the other category",
			len(byCategory.Items), has(byCategory.Items, ids[2]))
	}

	byBrand, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, Brand: "Aurora", Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue(brand): %v", err)
	}
	if len(byBrand.Items) != 2 || has(byBrand.Items, ids[1]) {
		t.Errorf("brand filter returned %d items and %v for the other brand",
			len(byBrand.Items), has(byBrand.Items, ids[1]))
	}
}

// brand was written by nothing and selected by nothing — the column existed
// (migration 100), the dashboard had an input for it, and the value went
// nowhere. This is the SELECT half of that.
func TestCatalogueReturnsTheBrandItStores(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-brandcol-" + itoa(int(runTag))
	makeProducts(t, pool, seed{name: tag + "-a", brand: "Aurora", price: 100})

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{Q: tag, Limit: 10})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	if len(page.Items) != 1 {
		t.Fatalf("got %d items, want 1", len(page.Items))
	}
	if page.Items[0].Brand != "Aurora" {
		t.Errorf("brand = %q, want %q — the column is stored and never read back",
			page.Items[0].Brand, "Aurora")
	}
}

// The العلامات التجارية chips need the list of brands that exist, counted over
// the whole catalogue rather than over whichever page happens to be loaded.
func TestCatalogueBrandFacetCountsTheWholeCatalogue(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-facet-" + itoa(int(runTag))
	brand := "Zephyr" + itoa(int(runTag))
	makeProducts(t, pool,
		seed{name: tag + "-a", brand: brand, price: 100},
		seed{name: tag + "-b", brand: brand, price: 100},
		seed{name: tag + "-c", brand: brand, price: 100, status: "pending"},
		seed{name: tag + "-d", price: 100}, // no brand — must not become a blank chip
	)

	page, err := NewStore(pool).ListBrands(context.Background(), 1, 200)
	if err != nil {
		t.Fatalf("ListBrands: %v", err)
	}
	var found *BrandFacet
	for i := range page.Items {
		if page.Items[i].Brand == brand {
			found = &page.Items[i]
		}
		if page.Items[i].Brand == "" {
			t.Errorf("the brand list contains an empty brand — that is every product " +
				"nobody has filled a brand in for, rendered as a nameless chip")
		}
	}
	if found == nil {
		t.Fatalf("brand %q is missing from the brand list", brand)
	}
	// Only the two APPROVED ones are in the public catalogue, so a chip
	// promising three would take the user to a page of two.
	if found.ProductCount != 2 {
		t.Errorf("product_count = %d for %q, want 2 (the pending one is not public)",
			found.ProductCount, brand)
	}
}

// ─── التصفية — price range and availability ─────────────────────────────

func TestCatalogueFiltersByPriceRangeAndStock(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-range-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-cheap", price: 500, stock: intPtr(4)},
		seed{name: tag + "-mid", price: 5000, stock: intPtr(0)},
		seed{name: tag + "-dear", price: 50000, stock: nil}, // NULL = unlimited
	)

	inRange, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, MinPrice: 1000, MaxPrice: 10000, Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue(price): %v", err)
	}
	if len(inRange.Items) != 1 || inRange.Items[0].ID != ids[1] {
		t.Errorf("price range 1000–10000 returned %d items, want only the 5000 one", len(inRange.Items))
	}

	inStock, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, InStockOnly: true, Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue(stock): %v", err)
	}
	if has(inStock.Items, ids[1]) {
		t.Errorf("a product with stock_quantity = 0 is in the in-stock feed")
	}
	// A NULL stock quantity has always meant "not tracked", not "none left" —
	// treating it as out of stock would empty the shelf of every product whose
	// seller never entered a count.
	if !has(inStock.Items, ids[2]) {
		t.Errorf("a product with NULL stock_quantity was filtered out of the in-stock feed")
	}
	if !has(inStock.Items, ids[0]) {
		t.Errorf("a product with stock_quantity = 4 is missing from the in-stock feed")
	}
}

// ─── Behaviour that must NOT change ─────────────────────────────────────

// The public catalogue has always shown approved products only. Every filter
// added above runs inside that rule, not around it.
func TestCatalogueStillShowsOnlyApprovedProducts(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-status-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-ok", price: 100},
		seed{name: tag + "-pending", price: 100, status: "pending"},
		seed{name: tag + "-hidden", price: 100, status: "hidden"},
	)

	for _, f := range []ProductFilters{
		{Q: tag, Limit: 10},
		{Q: tag, Limit: 10, Sort: SortNewest},
		{Q: tag, Limit: 10, Sort: SortBestSelling},
		{Q: tag, Limit: 10, Sort: SortPriceAsc},
	} {
		page, err := NewStore(pool).ListCatalogue(context.Background(), f)
		if err != nil {
			t.Fatalf("ListCatalogue(%+v): %v", f, err)
		}
		if len(page.Items) != 1 || page.Items[0].ID != ids[0] {
			t.Errorf("sort=%q leaked a non-approved product: got %d items", f.Sort, len(page.Items))
		}
	}
}

// An unknown sort must fall back to the catalogue's long-standing order rather
// than erroring or, worse, being interpolated into the SQL.
func TestCatalogueUnknownSortFallsBackToNewestIDFirst(t *testing.T) {
	pool := newTestPool(t)
	tag := "k15-badsort-" + itoa(int(runTag))
	ids := makeProducts(t, pool,
		seed{name: tag + "-a", price: 100},
		seed{name: tag + "-b", price: 100},
	)

	page, err := NewStore(pool).ListCatalogue(context.Background(), ProductFilters{
		Q: tag, Sort: "id DESC; DROP TABLE marketplace_products", Limit: 10,
	})
	if err != nil {
		t.Fatalf("ListCatalogue: %v", err)
	}
	if len(page.Items) != 2 || page.Items[0].ID != ids[1] {
		t.Errorf("an unrecognised sort changed the result instead of falling back to id DESC")
	}
}
