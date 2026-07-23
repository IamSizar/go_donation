package marriage

import (
	"context"
	"errors"
	"strings"
)

// SubscriptionPackage is an admin-managed marriage subscription tier.
// Replaces the old fixed 5-tier enum — admin can add/edit/reorder/delete
// these freely, same shape as payment methods.
type SubscriptionPackage struct {
	ID              int64  `json:"id"`
	Slug            string `json:"slug"`
	NameEn          string `json:"name_en"`
	NameAr          string `json:"name_ar"`
	NameCkb         string `json:"name_ckb"`
	NameKmr         string `json:"name_kmr"`
	DescriptionEn   string `json:"description_en"`
	DescriptionAr   string `json:"description_ar"`
	DescriptionCkb  string `json:"description_ckb"`
	DescriptionKmr  string `json:"description_kmr"`
	PriceIQD        int64  `json:"price_iqd"`
	DisplayOrder    int    `json:"display_order"`
	Active          bool   `json:"active"`
}

// ErrPackageNotFound / ErrPurchaseNotFound mirror the wallet/tasks packages'
// not-found sentinel convention.
var (
	ErrPackageNotFound  = errors.New("subscription package not found")
	ErrPurchaseNotFound = errors.New("subscription purchase not found")
)

// ListPackages returns packages ordered for display. activeOnly=true is the
// public/user-facing view; false is the admin management view (sees
// deactivated packages too, so they can be reactivated).
func (s *Store) ListPackages(ctx context.Context, activeOnly bool) ([]SubscriptionPackage, error) {
	// active is stored as SMALLINT (0/1), same convention as payment_methods
	// — cast to a boolean expression so it scans straight into a Go bool.
	q := `SELECT id, slug, name_en, name_ar, name_ckb, name_kmr,
	             description_en, description_ar, description_ckb, description_kmr,
	             price_iqd, display_order, (active = 1)
	        FROM marriage_subscription_packages`
	if activeOnly {
		q += ` WHERE active = 1`
	}
	q += ` ORDER BY display_order, id`
	rows, err := s.Pool.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SubscriptionPackage{}
	for rows.Next() {
		var p SubscriptionPackage
		if err := rows.Scan(&p.ID, &p.Slug, &p.NameEn, &p.NameAr, &p.NameCkb, &p.NameKmr,
			&p.DescriptionEn, &p.DescriptionAr, &p.DescriptionCkb, &p.DescriptionKmr,
			&p.PriceIQD, &p.DisplayOrder, &p.Active); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// GetPackage fetches one package by id.
func (s *Store) GetPackage(ctx context.Context, id int64) (SubscriptionPackage, error) {
	var p SubscriptionPackage
	err := s.Pool.QueryRow(ctx,
		`SELECT id, slug, name_en, name_ar, name_ckb, name_kmr,
		        description_en, description_ar, description_ckb, description_kmr,
		        price_iqd, display_order, (active = 1)
		   FROM marriage_subscription_packages WHERE id = $1`, id,
	).Scan(&p.ID, &p.Slug, &p.NameEn, &p.NameAr, &p.NameCkb, &p.NameKmr,
		&p.DescriptionEn, &p.DescriptionAr, &p.DescriptionCkb, &p.DescriptionKmr,
		&p.PriceIQD, &p.DisplayOrder, &p.Active)
	if err != nil {
		return SubscriptionPackage{}, ErrPackageNotFound
	}
	return p, nil
}

// AddPackage creates a new package and returns its id.
func (s *Store) AddPackage(ctx context.Context, p SubscriptionPackage) (int64, error) {
	slug := strings.TrimSpace(p.Slug)
	if slug == "" || strings.TrimSpace(p.NameEn) == "" {
		return 0, errors.New("slug and name_en are required")
	}
	activeInt := 0
	if p.Active {
		activeInt = 1
	}
	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO marriage_subscription_packages
		   (slug, name_en, name_ar, name_ckb, name_kmr,
		    description_en, description_ar, description_ckb, description_kmr,
		    price_iqd, display_order, active)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		RETURNING id`,
		slug, p.NameEn, p.NameAr, p.NameCkb, p.NameKmr,
		p.DescriptionEn, p.DescriptionAr, p.DescriptionCkb, p.DescriptionKmr,
		p.PriceIQD, p.DisplayOrder, activeInt,
	).Scan(&id)
	return id, err
}

// UpdatePackage overwrites every field of an existing package (the admin-web
// form always sends the full record, same as payment methods' Update).
func (s *Store) UpdatePackage(ctx context.Context, id int64, p SubscriptionPackage) error {
	activeInt := 0
	if p.Active {
		activeInt = 1
	}
	ct, err := s.Pool.Exec(ctx, `
		UPDATE marriage_subscription_packages SET
		   name_en = $2, name_ar = $3, name_ckb = $4, name_kmr = $5,
		   description_en = $6, description_ar = $7, description_ckb = $8, description_kmr = $9,
		   price_iqd = $10, active = $11, updated_at = now()
		 WHERE id = $1`,
		id, p.NameEn, p.NameAr, p.NameCkb, p.NameKmr,
		p.DescriptionEn, p.DescriptionAr, p.DescriptionCkb, p.DescriptionKmr,
		p.PriceIQD, activeInt,
	)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return ErrPackageNotFound
	}
	return nil
}

// ReorderPackages sets display_order to match the given id sequence.
func (s *Store) ReorderPackages(ctx context.Context, ids []int64) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	for i, id := range ids {
		if _, err := tx.Exec(ctx,
			`UPDATE marriage_subscription_packages SET display_order = $2, updated_at = now() WHERE id = $1`,
			id, i+1,
		); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// DeletePackage removes a package outright. Existing profiles that already
// hold this package's slug as their subscription_status are untouched (no
// FK there by design — deleting a package must not corrupt a profile's
// history of what it once purchased).
func (s *Store) DeletePackage(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM marriage_subscription_packages WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return ErrPackageNotFound
	}
	return nil
}

// Purchase is one subscription purchase attempt.
type Purchase struct {
	ID            int64  `json:"id"`
	ProfileID     int64  `json:"profile_id"`
	UserID        int64  `json:"user_id"`
	PackageID     int64  `json:"package_id"`
	PackageSlug   string `json:"package_slug"`
	PackageName   string `json:"package_name_en"`
	PriceIQD      int64  `json:"price_iqd"`
	PaymentMethod string `json:"payment_method"`
	Status        string `json:"status"`
	CreatedAt     string `json:"created_at"`
	ConfirmedAt   *string `json:"confirmed_at,omitempty"`
}

// CreatePaidPurchase records an already-paid purchase (wallet debit already
// succeeded) and activates it on the profile immediately, atomically.
func (s *Store) CreatePaidPurchase(ctx context.Context, profileID, userID, packageID, priceIQD int64,
	paymentMethod, packageSlug string) (int64, error) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var id int64
	if err := tx.QueryRow(ctx, `
		INSERT INTO marriage_subscription_purchases
		   (profile_id, user_id, package_id, price_iqd, payment_method, status, confirmed_at)
		VALUES ($1, $2, $3, $4, $5, 'paid', now())
		RETURNING id`,
		profileID, userID, packageID, priceIQD, paymentMethod,
	).Scan(&id); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE marriage_profiles SET subscription_status = $2, updated_at = now() WHERE id = $1`,
		profileID, packageSlug,
	); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return id, nil
}

// CreatePendingPurchase records a purchase awaiting staff confirmation (cash/
// bank payment methods) — the profile's tier does NOT change until confirmed.
func (s *Store) CreatePendingPurchase(ctx context.Context, profileID, userID, packageID, priceIQD int64,
	paymentMethod string) (int64, error) {
	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO marriage_subscription_purchases
		   (profile_id, user_id, package_id, price_iqd, payment_method, status)
		VALUES ($1, $2, $3, $4, $5, 'pending')
		RETURNING id`,
		profileID, userID, packageID, priceIQD, paymentMethod,
	).Scan(&id)
	return id, err
}

// ListPurchases returns purchases, newest first, optionally filtered by
// status (e.g. "pending" for the admin confirmation queue).
func (s *Store) ListPurchases(ctx context.Context, status string) ([]Purchase, error) {
	q := `SELECT pu.id, pu.profile_id, pu.user_id, pu.package_id,
	             pk.slug, pk.name_en, pu.price_iqd, pu.payment_method, pu.status,
	             pu.created_at::text, pu.confirmed_at::text
	        FROM marriage_subscription_purchases pu
	        JOIN marriage_subscription_packages pk ON pk.id = pu.package_id`
	args := []any{}
	if status != "" {
		q += ` WHERE pu.status = $1`
		args = append(args, status)
	}
	q += ` ORDER BY pu.id DESC`
	rows, err := s.Pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Purchase{}
	for rows.Next() {
		var p Purchase
		var confirmedAt *string
		if err := rows.Scan(&p.ID, &p.ProfileID, &p.UserID, &p.PackageID,
			&p.PackageSlug, &p.PackageName, &p.PriceIQD, &p.PaymentMethod, &p.Status,
			&p.CreatedAt, &confirmedAt); err != nil {
			return nil, err
		}
		p.ConfirmedAt = confirmedAt
		out = append(out, p)
	}
	return out, rows.Err()
}

// ConfirmPurchase marks a pending purchase paid and activates its package on
// the profile, atomically. Returns the profile's owner (for notifying them)
// and the package slug/name.
func (s *Store) ConfirmPurchase(ctx context.Context, purchaseID int64) (userID int64, packageName string, err error) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, "", err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var profileID, pkgID int64
	var status string
	if err := tx.QueryRow(ctx,
		`SELECT profile_id, user_id, package_id, status FROM marriage_subscription_purchases WHERE id = $1 FOR UPDATE`,
		purchaseID,
	).Scan(&profileID, &userID, &pkgID, &status); err != nil {
		return 0, "", ErrPurchaseNotFound
	}
	if status != "pending" {
		return 0, "", errors.New("purchase is not pending")
	}
	var slug string
	if err := tx.QueryRow(ctx,
		`SELECT slug, name_en FROM marriage_subscription_packages WHERE id = $1`, pkgID,
	).Scan(&slug, &packageName); err != nil {
		return 0, "", ErrPackageNotFound
	}
	if _, err := tx.Exec(ctx,
		`UPDATE marriage_subscription_purchases SET status = 'paid', confirmed_at = now() WHERE id = $1`,
		purchaseID,
	); err != nil {
		return 0, "", err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE marriage_profiles SET subscription_status = $2, updated_at = now() WHERE id = $1`,
		profileID, slug,
	); err != nil {
		return 0, "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, "", err
	}
	return userID, packageName, nil
}

// RejectPurchase marks a pending purchase rejected (e.g. cash never arrived)
// without touching the profile's tier.
func (s *Store) RejectPurchase(ctx context.Context, purchaseID int64) (userID int64, err error) {
	err = s.Pool.QueryRow(ctx,
		`UPDATE marriage_subscription_purchases SET status = 'rejected'
		  WHERE id = $1 AND status = 'pending'
		  RETURNING user_id`,
		purchaseID,
	).Scan(&userID)
	if err != nil {
		return 0, ErrPurchaseNotFound
	}
	return userID, nil
}
