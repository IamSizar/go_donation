// catalogue.go — K15: the public product catalogue, with the sorts and filters
// the client's six functional labels need.
//
// WHAT THIS FILE REPLACES
// The public list used to be `ListProducts(ctx, page, limit)`: no filter, no
// sort, `ORDER BY id DESC`, and created_at not even selected. Every one of the
// six labels the spec names — الأكثر مبيعاً, وصل حديثاً, العروض والخصومات,
// التصفية, الفئات, العلامات التجارية — is a statement about the WHOLE
// catalogue, and the app was only ever handed one page of twenty rows. Chips
// built on that could sort what they were holding and nothing more, so
// "الأكثر مبيعاً" would have named the best seller of one page.
//
// Everything here is therefore expressed as SQL over the whole table:
// the filters are WHERE conditions, the sorts are ORDER BY clauses, and the
// count is a COUNT — so page 1 of a sorted catalogue really is the top of it.
//
// SQL SAFETY
// Every user-supplied value is a bound parameter. The only strings ever
// concatenated into a statement are package-level literals chosen by a switch
// (the ORDER BY clauses) — an unrecognised sort falls back to the default
// rather than reaching the query. See orderByFor.
package marketplace

import (
	"context"
	"fmt"
	"strings"
)

// ─── Sort options ───────────────────────────────────────────────────────

// The sort values the app may ask for. They are named after the label each one
// powers, not after the column, because the label is the contract: if the way
// "best selling" is computed ever changes, the app should not have to.
const (
	// SortNewest — وصل حديثاً.
	SortNewest = "newest"
	// SortBestSelling — الأكثر مبيعاً.
	SortBestSelling = "best_selling"
	// SortPriceAsc / SortPriceDesc — التصفية's price ordering.
	SortPriceAsc  = "price_asc"
	SortPriceDesc = "price_desc"
)

// orderByFor maps a requested sort to a LITERAL ORDER BY clause. Anything
// unrecognised — including a hostile string — falls through to the default,
// which is the ordering the catalogue has always had. Nothing from the request
// is ever interpolated.
//
// Every clause ends in `p.id DESC` so paging is stable: without a unique
// tiebreaker two products sharing a price (or a sales count, of which zero is
// by far the commonest) could swap places between page 1 and page 2 and be
// shown twice, or not at all.
func orderByFor(sort string) string {
	switch strings.TrimSpace(sort) {
	case SortNewest:
		return "p.created_at DESC, p.id DESC"
	case SortBestSelling:
		return "sold_count DESC, p.id DESC"
	case SortPriceAsc:
		return "p.price ASC, p.id DESC"
	case SortPriceDesc:
		return "p.price DESC, p.id DESC"
	default:
		return "p.id DESC"
	}
}

// ─── Request and response shapes ────────────────────────────────────────

// ProductFilters is one request for a page of the public catalogue. A zero
// value asks for exactly what the old ListProducts returned: page 1, the
// twenty newest-by-id approved products.
type ProductFilters struct {
	Page  int
	Limit int
	// Q searches name / Arabic name / description / SKU / brand.
	Q string
	// CategorySlug — الفئات. Matches marketplace_categories.slug.
	CategorySlug string
	// Brand — العلامات التجارية. Exact match; the app gets the list of real
	// brand names from ListBrands, so there is nothing to guess at.
	Brand string
	// Label — one badge from the fixed set (new/sale/featured/used/in_stock).
	Label string
	// OnSale — العروض والخصومات.
	OnSale bool
	// InStockOnly — التصفية's availability switch.
	InStockOnly bool
	// MinPrice / MaxPrice — التصفية's price range. 0 means "no bound", which
	// is safe because a product priced at 0 is free rather than filtered.
	MinPrice float64
	MaxPrice float64
	// Sort — one of the Sort* constants; anything else means the default.
	Sort string
}

// Page is the envelope every public catalogue list returns. Its field names
// deliberately match AdminPage's, so the app and the dashboard read one shape
// rather than two — but it is a separate type because AdminPage describes the
// dashboard's contract and this one describes the app's, and they are free to
// diverge without breaking each other.
type Page[T any] struct {
	Items      []T  `json:"items"`
	Page       int  `json:"page"`
	PerPage    int  `json:"per_page"`
	TotalItems int  `json:"total_items"`
	TotalPages int  `json:"total_pages"`
	HasMore    bool `json:"has_more"`
}

// CatalogueProduct is a Product plus the two values the catalogue computes
// rather than stores. They live here and not on Product because the dashboard's
// product list does not compute them, and a field that is silently zero in one
// caller and meaningful in another is how a number ends up being trusted when
// it should not be.
type CatalogueProduct struct {
	Product
	// SoldCount is the quantity ordered across confirmed orders — what
	// الأكثر مبيعاً is ranked by, exposed so a chip claiming "best selling"
	// can show the figure it is claiming.
	SoldCount int `json:"sold_count"`
	// PriceAfterDiscount is price with discount_percent applied, already
	// rounded. Computed once here so four clients cannot round it four ways;
	// equals price when there is no discount, so the app has one field to
	// print rather than a branch to get wrong.
	PriceAfterDiscount string `json:"price_after_discount"`
}

// confirmedOrderStatuses — what counts as a sale for الأكثر مبيعاً.
// 'pending' is excluded because it is a request nobody has accepted yet, and
// 'cancelled' because it is a sale that un-happened; ranking on either would
// let an unconfirmed basket outrank a real one.
const confirmedOrderStatuses = `('approved','processing','completed')`

// catalogueColumns is the SELECT list, shared by every sort so the response
// shape never depends on which chip the user tapped.
const catalogueColumns = `
	p.id, p.seller_user_id, p.beneficiary_case_id,
	p.name, p.name_ar, p.name_sorani, p.name_badini,
	p.description, p.description_ar, p.description_sorani, p.description_badini,
	p.category, p.price::text, p.currency, p.image_path, p.stock_quantity, p.status,
	p.category_slug, p.sku, p.specs, COALESCE(p.labels, '{}'),
	p.brand, p.discount_percent, p.created_at,
	COALESCE(s.sold, 0) AS sold_count,
	ROUND(p.price * (100 - COALESCE(p.discount_percent, 0)) / 100.0, 2)::text`

// soldJoin aggregates confirmed order quantities per product. It is a grouped
// scan of marketplace_orders however the catalogue is sorted — see migration
// 109 for why no extra index would help — and is joined unconditionally so
// sold_count means the same thing on every response.
const soldJoin = `
	LEFT JOIN (SELECT product_id, SUM(quantity)::bigint AS sold
	             FROM marketplace_orders
	            WHERE status IN ` + confirmedOrderStatuses + `
	            GROUP BY product_id) s ON s.product_id = p.id`

// ─── The catalogue query ────────────────────────────────────────────────

// ListCatalogue returns one page of approved products, filtered and sorted
// over the whole catalogue.
func (s *Store) ListCatalogue(ctx context.Context, f ProductFilters) (*Page[CatalogueProduct], error) {
	page, perPage := normalizePaging(f.Page, f.Limit)
	where, args := f.build()

	var total int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM marketplace_products p `+where, args...,
	).Scan(&total); err != nil {
		return nil, fmt.Errorf("count catalogue products: %w", err)
	}

	args = append(args, perPage, (page-1)*perPage)
	rows, err := s.Pool.Query(ctx,
		`SELECT`+catalogueColumns+`
		   FROM marketplace_products p`+soldJoin+` `+where+`
		  ORDER BY `+orderByFor(f.Sort)+`
		  LIMIT $`+itoa(len(args)-1)+` OFFSET $`+itoa(len(args)),
		args...,
	)
	if err != nil {
		return nil, fmt.Errorf("list catalogue products: %w", err)
	}
	defer rows.Close()

	items := []CatalogueProduct{}
	for rows.Next() {
		var p CatalogueProduct
		if err := rows.Scan(
			&p.ID, &p.SellerUserID, &p.BeneficiaryCaseID,
			&p.Name, &p.NameAr, &p.NameSorani, &p.NameBadini,
			&p.Description, &p.DescriptionAr, &p.DescriptionSorani, &p.DescriptionBadini,
			&p.Category, &p.Price, &p.Currency, &p.ImagePath, &p.StockQuantity, &p.Status,
			&p.CategorySlug, &p.SKU, &p.Specs, &p.Labels,
			&p.Brand, &p.DiscountPercent, &p.CreatedAt,
			&p.SoldCount, &p.PriceAfterDiscount,
		); err != nil {
			return nil, fmt.Errorf("scan catalogue product: %w", err)
		}
		items = append(items, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read catalogue products: %w", err)
	}
	return newPage(items, page, perPage, total), nil
}

// build turns the filters into a WHERE clause and its bound arguments.
//
// `p.status = 'approved'` is not a filter and is not optional: the public
// catalogue has only ever shown approved products, and every option below
// narrows that set rather than replacing it.
func (f ProductFilters) build() (string, []any) {
	args := []any{}
	conds := []string{"p.status = 'approved'"}

	if q := strings.TrimSpace(f.Q); q != "" {
		args = append(args, "%"+q+"%")
		i := itoa(len(args))
		conds = append(conds, "(p.name ILIKE $"+i+" OR p.name_ar ILIKE $"+i+
			" OR p.description ILIKE $"+i+" OR p.sku ILIKE $"+i+" OR p.brand ILIKE $"+i+")")
	}
	if v := strings.TrimSpace(f.CategorySlug); v != "" {
		args = append(args, v)
		conds = append(conds, "p.category_slug = $"+itoa(len(args)))
	}
	if v := strings.TrimSpace(f.Brand); v != "" {
		args = append(args, v)
		conds = append(conds, "p.brand = $"+itoa(len(args)))
	}
	if v := strings.TrimSpace(f.Label); v != "" {
		// Containment (@>) rather than = ANY, so the GIN index added in
		// migration 109 can actually serve it.
		args = append(args, []string{strings.ToLower(v)})
		conds = append(conds, "p.labels @> $"+itoa(len(args)))
	}
	if f.OnSale {
		// Two ways to be on offer, and both must count. discount_percent is
		// new; the 'sale' badge has existed since migration 036 and is what
		// staff have been tagging offers with all along, so an offers feed
		// that only understood the new column would have emptied the shelf of
		// every existing offer on the day it shipped.
		conds = append(conds, "(p.discount_percent IS NOT NULL OR p.labels @> ARRAY['sale']::text[])")
	}
	if f.InStockOnly {
		// NULL has always meant "stock not tracked", not "none left" —
		// treating it as out of stock would hide every product whose seller
		// never entered a count.
		conds = append(conds, "(p.stock_quantity IS NULL OR p.stock_quantity > 0)")
	}
	if f.MinPrice > 0 {
		args = append(args, f.MinPrice)
		conds = append(conds, "p.price >= $"+itoa(len(args)))
	}
	if f.MaxPrice > 0 {
		args = append(args, f.MaxPrice)
		conds = append(conds, "p.price <= $"+itoa(len(args)))
	}
	return "WHERE " + strings.Join(conds, " AND "), args
}

// ─── Brands facet (العلامات التجارية) ───────────────────────────────────

// BrandFacet is one brand chip: the name to print and how many products the
// user will actually find behind it.
type BrandFacet struct {
	Brand        string `json:"brand"`
	ProductCount int    `json:"product_count"`
}

// ListBrands returns the brands present in the PUBLIC catalogue, with counts,
// most-stocked first. Counting only approved products is the point: a chip
// that promised eleven and opened onto four would be the same page-shaped lie
// this whole change exists to remove.
//
// Paged like every other list endpoint. The result set is bounded by the number
// of distinct brands rather than by the catalogue size, so one page will
// normally hold all of them — but "normally" is not a guarantee, and an
// unbounded query that is usually small is still an unbounded query.
func (s *Store) ListBrands(ctx context.Context, page, limit int) (*Page[BrandFacet], error) {
	page, perPage := normalizePaging(page, limit)

	// Products with no brand are excluded rather than grouped under '': a
	// nameless chip is not something a user can choose.
	const from = ` FROM marketplace_products
	                WHERE status = 'approved' AND brand <> ''`

	var total int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(DISTINCT brand)`+from,
	).Scan(&total); err != nil {
		return nil, fmt.Errorf("count catalogue brands: %w", err)
	}

	rows, err := s.Pool.Query(ctx,
		`SELECT brand, COUNT(*)::int`+from+`
		  GROUP BY brand
		  ORDER BY COUNT(*) DESC, brand ASC
		  LIMIT $1 OFFSET $2`,
		perPage, (page-1)*perPage,
	)
	if err != nil {
		return nil, fmt.Errorf("list catalogue brands: %w", err)
	}
	defer rows.Close()

	items := []BrandFacet{}
	for rows.Next() {
		var b BrandFacet
		if err := rows.Scan(&b.Brand, &b.ProductCount); err != nil {
			return nil, fmt.Errorf("scan catalogue brand: %w", err)
		}
		items = append(items, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read catalogue brands: %w", err)
	}
	return newPage(items, page, perPage, total), nil
}

// ─── Paging helpers ─────────────────────────────────────────────────────

// normalizePaging clamps a requested page and page size to the same bounds the
// rest of this package uses, so no caller can ask for an unbounded read.
func normalizePaging(page, limit int) (int, int) {
	if page < 1 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	return page, limit
}

// newPage fills in the derived fields so has_more is arithmetic rather than the
// old guess (`len(items) >= limit`), which claimed there was another page every
// time the last one happened to be exactly full.
func newPage[T any](items []T, page, perPage, total int) *Page[T] {
	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &Page[T]{
		Items: items, Page: page, PerPage: perPage,
		TotalItems: total, TotalPages: totalPages, HasMore: page < totalPages,
	}
}
