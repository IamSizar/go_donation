// Package donationtypes backs the admin-managed donor-facing donation-type
// list (M7): an ordered, 4-language taxonomy the donor picks from on the
// donate screen — general / zakat / sadaqah, plus whatever staff add later.
//
// Before migration 103 this set was a closed switch in Go, so a fourth type
// meant a code change and a redeploy — the one part of the client's "full
// control from the dashboard without a software update" that was not a row.
//
// Mirrors the inkindcategories / projectcategories CMS pattern exactly (slug +
// 4 language names + display_order + active) so the admin routes, the SPA page
// and the Trash/restore path (H15) all carry over unchanged.
//
// NOT to be confused with donation_KIND (general/campaign/sponsorship/in_kind/
// operational). That is internal routing, carries a live CHECK constraint, and
// each value has a flow behind it — see the header of migration 103.
package donationtypes

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Type is one donation type with its 4-language display names.
type Type struct {
	ID           int64  `json:"id"`
	Slug         string `json:"slug"`
	NameEN       string `json:"name_en"`
	NameAR       string `json:"name_ar"`
	NameCKB      string `json:"name_ckb"`
	NameKMR      string `json:"name_kmr"`
	DisplayOrder int    `json:"display_order"`
	Active       bool   `json:"active"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

var slugStripRE = regexp.MustCompile(`[^a-z0-9]+`)

// slugify turns a free-text name into a canonical slug: lowercased, non-alnum
// runs collapsed to a single underscore. The slug is what lands in
// donations.donation_type, so it must stay ASCII and stable.
func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugStripRE.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

// List returns types in admin-defined display order (id tiebreak). When
// activeOnly, only active rows — that is the shape the app's donate screen
// asks for, and it is served by idx_donation_types_active_order.
func (s *Store) List(ctx context.Context, activeOnly bool) ([]Type, error) {
	where := ""
	if activeOnly {
		where = " WHERE active = 1"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT id, slug, name_en, name_ar, name_ckb, name_kmr, display_order, (active = 1)
		   FROM donation_types`+where+`
		  ORDER BY display_order, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Type{}
	for rows.Next() {
		var d Type
		if err := rows.Scan(&d.ID, &d.Slug, &d.NameEN, &d.NameAR, &d.NameCKB, &d.NameKMR,
			&d.DisplayOrder, &d.Active); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// IsActiveSlug reports whether slug names a currently active donation type.
//
// This is the guard the donate path calls on every gift, which is why it is a
// single indexed lookup (donation_types_slug_key) and returns a plain bool
// rather than a row: the caller only needs "may a donor file under this?".
// A lookup error is returned, never swallowed — the caller decides whether to
// degrade, because refusing a donation over an unreachable lookup table would
// be the worse outcome.
func (s *Store) IsActiveSlug(ctx context.Context, slug string) (bool, error) {
	if s == nil || s.Pool == nil {
		return false, errors.New("donation types store not wired")
	}
	slug = strings.TrimSpace(slug)
	if slug == "" {
		return false, nil
	}
	var ok bool
	if err := s.Pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM donation_types WHERE slug = $1 AND active = 1)`,
		slug,
	).Scan(&ok); err != nil {
		return false, err
	}
	return ok, nil
}

// Add inserts a new type, deriving the slug from the English name (or an
// explicit slug). New types are active. Returns the stored row.
func (s *Store) Add(ctx context.Context, d Type, actorID *int64) (*Type, error) {
	d.NameEN = strings.TrimSpace(d.NameEN)
	if d.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	key := slugify(d.Slug)
	if key == "" {
		key = slugify(d.NameEN)
	}
	if key == "" {
		return nil, errors.New("could not derive a donation-type key")
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO donation_types (slug, name_en, name_ar, name_ckb, name_kmr, active, created_by)
		 VALUES ($1, $2, $3, $4, $5, 1, $6)
		 RETURNING id, display_order, (active = 1)`,
		key, d.NameEN, strings.TrimSpace(d.NameAR),
		strings.TrimSpace(d.NameCKB), strings.TrimSpace(d.NameKMR), actorID,
	).Scan(&id, &d.DisplayOrder, &d.Active)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("a donation type with that name already exists")
		}
		return nil, err
	}
	d.ID = id
	d.Slug = key
	return &d, nil
}

// Update edits a type's names and active flag.
//
// The slug is deliberately immutable: it is the value already written into
// donations.donation_type on every past gift, so renaming it would orphan
// history. Staff rename the *labels*, which is what the dashboard shows.
func (s *Store) Update(ctx context.Context, id int64, d Type) (*Type, error) {
	d.NameEN = strings.TrimSpace(d.NameEN)
	if d.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	activeInt := 0
	if d.Active {
		activeInt = 1
	}
	var out Type
	err := s.Pool.QueryRow(ctx,
		`UPDATE donation_types
		    SET name_en = $2, name_ar = $3, name_ckb = $4, name_kmr = $5, active = $6
		  WHERE id = $1
		  RETURNING id, slug, name_en, name_ar, name_ckb, name_kmr, display_order, (active = 1)`,
		id, d.NameEN, strings.TrimSpace(d.NameAR),
		strings.TrimSpace(d.NameCKB), strings.TrimSpace(d.NameKMR), activeInt,
	).Scan(&out.ID, &out.Slug, &out.NameEN, &out.NameAR, &out.NameCKB, &out.NameKMR,
		&out.DisplayOrder, &out.Active)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			return nil, errors.New("donation type not found")
		}
		return nil, err
	}
	return &out, nil
}

// Reorder rewrites display_order to match the given id sequence (first id → 1,
// etc.) in a single transaction, so a partial reorder can never be observed.
func (s *Store) Reorder(ctx context.Context, orderedIDs []int64) error {
	if len(orderedIDs) == 0 {
		return nil
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for i, id := range orderedIDs {
		if _, err := tx.Exec(ctx,
			`UPDATE donation_types SET display_order = $2 WHERE id = $1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Delete removes a type. Past donations keep the slug already stored in
// donations.donation_type; the type simply drops out of the donate screen.
//
// H15 — the admin route does NOT call this: DELETE goes through
// handlers.trashRow so the row lands in the Trash and can be restored. Kept as
// the low-level primitive; wiring it to a route again makes that route
// permanently destructive.
func (s *Store) Delete(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM donation_types WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("donation type not found")
	}
	return nil
}
