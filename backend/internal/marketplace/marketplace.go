package marketplace

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Product is the row shape returned by GET /api/marketplace.
type Product struct {
	ID                 int64   `json:"id"`
	SellerUserID       *int    `json:"seller_user_id"`
	BeneficiaryCaseID  *int64  `json:"beneficiary_case_id"`
	Name               string  `json:"name"`
	NameAr             *string `json:"name_ar"`
	NameSorani         *string `json:"name_sorani"`
	NameBadini         *string `json:"name_badini"`
	Description        *string `json:"description"`
	DescriptionAr      *string `json:"description_ar"`
	DescriptionSorani  *string `json:"description_sorani"`
	DescriptionBadini  *string `json:"description_badini"`
	Category           *string `json:"category"`
	Price              string  `json:"price"`
	Currency           string  `json:"currency"`
	ImagePath          *string `json:"image_path"`
	StockQuantity      *int    `json:"stock_quantity"`
	Status             string  `json:"status"`
	// #28 — CMS category + SKU + specs + labels.
	CategorySlug *string  `json:"category_slug"`
	SKU          *string  `json:"sku"`
	Specs        *string  `json:"specs"`
	Labels       []string `json:"labels"`
}

// Order is the row shape returned by ?view=orders.
type Order struct {
	ID              int64     `json:"id"`
	ProductID       int64     `json:"product_id"`
	BuyerUserID     *int      `json:"buyer_user_id"`
	Quantity        int       `json:"quantity"`
	TotalAmount     string    `json:"total_amount"`
	Currency        string    `json:"currency"`
	Status          string    `json:"status"`
	BuyerNote       *string   `json:"buyer_note"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
	// Joined product columns:
	Name              *string `json:"name"`
	NameAr            *string `json:"name_ar"`
	NameSorani        *string `json:"name_sorani"`
	NameBadini        *string `json:"name_badini"`
	Category          *string `json:"category"`
	ImagePath         *string `json:"image_path"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{Pool: pool}
}

// ListProducts returns approved products, paged.
func (s *Store) ListProducts(ctx context.Context, page, limit int) ([]Product, error) {
	if page < 1 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	offset := (page - 1) * limit

	rows, err := s.Pool.Query(ctx, `
		SELECT id, seller_user_id, beneficiary_case_id,
		       name, name_ar, name_sorani, name_badini,
		       description, description_ar, description_sorani, description_badini,
		       category, price::text, currency, image_path, stock_quantity, status,
		       category_slug, sku, specs, COALESCE(labels, '{}')
		  FROM marketplace_products
		 WHERE status = 'approved'
		 ORDER BY id DESC
		 LIMIT $1 OFFSET $2`,
		limit, offset,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Product{}
	for rows.Next() {
		var p Product
		err := rows.Scan(
			&p.ID, &p.SellerUserID, &p.BeneficiaryCaseID,
			&p.Name, &p.NameAr, &p.NameSorani, &p.NameBadini,
			&p.Description, &p.DescriptionAr, &p.DescriptionSorani, &p.DescriptionBadini,
			&p.Category, &p.Price, &p.Currency, &p.ImagePath, &p.StockQuantity, &p.Status,
			&p.CategorySlug, &p.SKU, &p.Specs, &p.Labels,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, p)
	}
	return items, rows.Err()
}

// ListOrdersForUser returns the buyer's orders + joined product columns, paged.
func (s *Store) ListOrdersForUser(ctx context.Context, userID int64, page, limit int) ([]Order, error) {
	if userID <= 0 {
		return nil, errors.New("invalid userID")
	}
	if page < 1 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	offset := (page - 1) * limit

	rows, err := s.Pool.Query(ctx, `
		SELECT o.id, o.product_id, o.buyer_user_id, o.quantity, o.total_amount::text,
		       o.currency, o.status, o.buyer_note, o.created_at, o.updated_at,
		       p.name, p.name_ar, NULL::text, NULL::text, p.category, p.image_path
		  FROM marketplace_orders o
		  LEFT JOIN marketplace_products p ON p.id = o.product_id
		 WHERE o.buyer_user_id = $1
		 ORDER BY o.created_at DESC, o.id DESC
		 LIMIT $2 OFFSET $3`,
		userID, limit, offset,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Order{}
	for rows.Next() {
		var o Order
		err := rows.Scan(
			&o.ID, &o.ProductID, &o.BuyerUserID, &o.Quantity, &o.TotalAmount,
			&o.Currency, &o.Status, &o.BuyerNote, &o.CreatedAt, &o.UpdatedAt,
			&o.Name, &o.NameAr, &o.NameSorani, &o.NameBadini, &o.Category, &o.ImagePath,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, o)
	}
	return items, rows.Err()
}

// AdminPage is a generic paginated result.
type AdminPage[T any] struct {
	Items      []T  `json:"items"`
	Page       int  `json:"page"`
	PerPage    int  `json:"per_page"`
	TotalItems int  `json:"total_items"`
	TotalPages int  `json:"total_pages"`
	HasMore    bool `json:"has_more"`
}

// AdminListProducts returns paginated products (all statuses, or filter to one).
func (s *Store) AdminListProducts(ctx context.Context, page, perPage int, status, q string) (*AdminPage[Product], error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 200 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	args := []any{}
	conds := []string{}
	if status != "" {
		args = append(args, status)
		conds = append(conds, "status = $"+itoa(len(args)))
	}
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		idx := itoa(len(args))
		conds = append(conds, "(name ILIKE $"+idx+" OR name_ar ILIKE $"+idx+" OR category ILIKE $"+idx+")")
	}
	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM marketplace_products"+where, args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, perPage, offset)
	rows, err := s.Pool.Query(ctx, `
		SELECT id, seller_user_id, beneficiary_case_id,
		       name, name_ar, name_sorani, name_badini,
		       description, description_ar, description_sorani, description_badini,
		       category, price::text, currency, image_path, stock_quantity, status,
		       category_slug, sku, specs, COALESCE(labels, '{}')
		  FROM marketplace_products`+where+`
		 ORDER BY id DESC
		 LIMIT $`+itoa(limitIdx)+` OFFSET $`+itoa(offsetIdx),
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Product{}
	for rows.Next() {
		var p Product
		if err := rows.Scan(
			&p.ID, &p.SellerUserID, &p.BeneficiaryCaseID,
			&p.Name, &p.NameAr, &p.NameSorani, &p.NameBadini,
			&p.Description, &p.DescriptionAr, &p.DescriptionSorani, &p.DescriptionBadini,
			&p.Category, &p.Price, &p.Currency, &p.ImagePath, &p.StockQuantity, &p.Status,
			&p.CategorySlug, &p.SKU, &p.Specs, &p.Labels,
		); err != nil {
			return nil, err
		}
		items = append(items, p)
	}
	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &AdminPage[Product]{
		Items: items, Page: page, PerPage: perPage,
		TotalItems: total, TotalPages: totalPages, HasMore: page < totalPages,
	}, rows.Err()
}

// AdminListOrders returns paginated marketplace orders across all buyers.
// q searches by the joined product name/category, and by the order id (if q
// parses as an integer).
func (s *Store) AdminListOrders(ctx context.Context, page, perPage int, status, q string) (*AdminPage[Order], error) {
	if page < 1 {
		page = 1
	}
	if perPage <= 0 || perPage > 200 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	args := []any{}
	conds := []string{}
	if status != "" {
		args = append(args, status)
		conds = append(conds, "o.status = $"+itoa(len(args)))
	}
	if qTrim := strings.TrimSpace(q); qTrim != "" {
		args = append(args, "%"+qTrim+"%")
		idx := itoa(len(args))
		// Join is below; we still need it for COUNT so we'll inline it there too.
		conds = append(conds, "(p.name ILIKE $"+idx+" OR p.category ILIKE $"+idx+" OR o.buyer_note ILIKE $"+idx+")")
	}
	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM marketplace_orders o
		   LEFT JOIN marketplace_products p ON p.id = o.product_id`+where, args...,
	).Scan(&total); err != nil {
		return nil, err
	}

	limitIdx := len(args) + 1
	offsetIdx := len(args) + 2
	args = append(args, perPage, offset)
	rows, err := s.Pool.Query(ctx, `
		SELECT o.id, o.product_id, o.buyer_user_id, o.quantity, o.total_amount::text,
		       o.currency, o.status, o.buyer_note, o.created_at, o.updated_at,
		       p.name, p.name_ar, NULL::text, NULL::text, p.category, p.image_path
		  FROM marketplace_orders o
		  LEFT JOIN marketplace_products p ON p.id = o.product_id`+where+`
		 ORDER BY o.created_at DESC, o.id DESC
		 LIMIT $`+itoa(limitIdx)+` OFFSET $`+itoa(offsetIdx),
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Order{}
	for rows.Next() {
		var o Order
		if err := rows.Scan(
			&o.ID, &o.ProductID, &o.BuyerUserID, &o.Quantity, &o.TotalAmount,
			&o.Currency, &o.Status, &o.BuyerNote, &o.CreatedAt, &o.UpdatedAt,
			&o.Name, &o.NameAr, &o.NameSorani, &o.NameBadini, &o.Category, &o.ImagePath,
		); err != nil {
			return nil, err
		}
		items = append(items, o)
	}
	totalPages := (total + perPage - 1) / perPage
	if totalPages < 1 {
		totalPages = 1
	}
	return &AdminPage[Order]{
		Items: items, Page: page, PerPage: perPage,
		TotalItems: total, TotalPages: totalPages, HasMore: page < totalPages,
	}, rows.Err()
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}

// CreateOrderResult — outcome enum so the handler can map to HTTP codes.
type CreateOrderResult int

const (
	OrderCreated CreateOrderResult = iota
	OrderProductNotFound
	OrderOutOfStock
)

// ProductPriceInfo reads a product's price/currency/stock the same way
// CreateOrder itself does, so a caller (Note #42 — wallet payment) can
// compute the exact total to debit BEFORE calling CreateOrder.
func (s *Store) ProductPriceInfo(ctx context.Context, productID int64) (price float64, currency string, stock *int, err error) {
	err = s.Pool.QueryRow(ctx, `
		SELECT price::float8, currency, stock_quantity
		  FROM marketplace_products
		 WHERE id = $1 AND status = 'approved'`,
		productID,
	).Scan(&price, &currency, &stock)
	return price, currency, stock, err
}

// CreateOrder validates the product, stock, then inserts. Returns the new id,
// a result code, and the stock count when result == OrderOutOfStock.
func (s *Store) CreateOrder(
	ctx context.Context,
	buyerUserID int64,
	productID int64,
	quantity int,
	buyerNote string,
) (newID int64, result CreateOrderResult, stockLeft int, err error) {
	if quantity < 1 {
		quantity = 1
	}
	buyerNote = strings.TrimSpace(buyerNote)
	if len(buyerNote) > 1000 {
		buyerNote = buyerNote[:1000]
	}

	var (
		price    float64
		currency string
		stock    *int
	)
	err = s.Pool.QueryRow(ctx, `
		SELECT price::float8, currency, stock_quantity
		  FROM marketplace_products
		 WHERE id = $1 AND status = 'approved'`,
		productID,
	).Scan(&price, &currency, &stock)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, OrderProductNotFound, 0, nil
		}
		return 0, OrderCreated, 0, err
	}
	if stock != nil && *stock > 0 && quantity > *stock {
		return 0, OrderOutOfStock, *stock, nil
	}

	total := price * float64(quantity)
	var noteArg any
	if buyerNote != "" {
		noteArg = buyerNote
	}

	err = s.Pool.QueryRow(ctx, `
		INSERT INTO marketplace_orders
		   (product_id, buyer_user_id, quantity, total_amount, currency, buyer_note)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id`,
		productID, buyerUserID, quantity, total, currency, noteArg,
	).Scan(&newID)
	if err != nil {
		return 0, OrderCreated, 0, err
	}
	return newID, OrderCreated, 0, nil
}
