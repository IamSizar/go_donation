// Package sponsorshiptypes backs the admin-managed recurring-assistance types
// behind the sponsorship schedule ("Eighth: 4. Scalability" — new types of
// assistance without programming changes).
//
// Migration 086 created the table and seeded four types for exactly this
// purpose, but nothing was ever wired to it: no store, no handler, no route
// and no dashboard page. Adding a type therefore still meant running SQL by
// hand, which is the opposite of what that requirement asks for. This is the
// missing half.
//
// sponsorships.sponsorship_type stays a free VARCHAR, so this is a curated
// picker over the same values rather than a constraint — existing rows keep
// working untouched, and deleting a type never orphans a sponsorship.
package sponsorshiptypes

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Type is one recurring-assistance type with its 4-language display names.
type Type struct {
	ID      int64  `json:"id"`
	Slug    string `json:"slug"`
	NameEN  string `json:"name_en"`
	NameAR  string `json:"name_ar"`
	NameCKB string `json:"name_ckb"`
	NameKMR string `json:"name_kmr"`
	// Recurrence suggested when staff pick this type.
	DefaultInterval string `json:"default_interval"`
	DisplayOrder    int    `json:"display_order"`
	Active          bool   `json:"active"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

var slugStripRE = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugStripRE.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

// The table's CHECK constraint accepts only these, so an invalid value has to
// be rejected here rather than surfacing as a 500 from Postgres.
var intervals = map[string]bool{
	"weekly": true, "monthly": true, "quarterly": true, "yearly": true,
}

func normalizeInterval(v string) string {
	v = strings.ToLower(strings.TrimSpace(v))
	if intervals[v] {
		return v
	}
	return "monthly"
}

const cols = `id, slug, name_en, name_ar, name_ckb, name_kmr,
              default_interval, display_order, (active = 1)`

func scanOne(row interface {
	Scan(...any) error
}) (*Type, error) {
	var t Type
	if err := row.Scan(&t.ID, &t.Slug, &t.NameEN, &t.NameAR, &t.NameCKB, &t.NameKMR,
		&t.DefaultInterval, &t.DisplayOrder, &t.Active); err != nil {
		return nil, err
	}
	return &t, nil
}

// List returns types in admin-defined display order. When activeOnly, only
// active rows — that is what the staff-facing picker should offer.
func (s *Store) List(ctx context.Context, activeOnly bool) ([]Type, error) {
	where := ""
	if activeOnly {
		where = " WHERE active = 1"
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT `+cols+` FROM sponsorship_types`+where+` ORDER BY display_order, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Type{}
	for rows.Next() {
		t, err := scanOne(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *t)
	}
	return out, rows.Err()
}

// Add inserts a new type, deriving the slug from the English name unless one
// is supplied. New types are active.
func (s *Store) Add(ctx context.Context, t Type, actorID *int64) (*Type, error) {
	t.NameEN = strings.TrimSpace(t.NameEN)
	if t.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	key := slugify(t.Slug)
	if key == "" {
		key = slugify(t.NameEN)
	}
	if key == "" {
		return nil, errors.New("could not derive a type key")
	}
	row := s.Pool.QueryRow(ctx,
		`INSERT INTO sponsorship_types
		   (slug, name_en, name_ar, name_ckb, name_kmr, default_interval, active, created_by)
		 VALUES ($1, $2, $3, $4, $5, $6, 1, $7)
		 RETURNING `+cols,
		key, t.NameEN, strings.TrimSpace(t.NameAR), strings.TrimSpace(t.NameCKB),
		strings.TrimSpace(t.NameKMR), normalizeInterval(t.DefaultInterval), actorID)
	out, err := scanOne(row)
	if err != nil {
		if strings.Contains(err.Error(), "23505") ||
			strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("a type with that name already exists")
		}
		return nil, err
	}
	return out, nil
}

// Update edits names, interval and the active flag. The slug is immutable —
// sponsorships store it as free text, so changing it would silently detach
// every existing record from its type.
func (s *Store) Update(ctx context.Context, id int64, t Type) (*Type, error) {
	t.NameEN = strings.TrimSpace(t.NameEN)
	if t.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	activeInt := 0
	if t.Active {
		activeInt = 1
	}
	row := s.Pool.QueryRow(ctx,
		`UPDATE sponsorship_types
		    SET name_en = $2, name_ar = $3, name_ckb = $4, name_kmr = $5,
		        default_interval = $6, active = $7
		  WHERE id = $1
		  RETURNING `+cols,
		id, t.NameEN, strings.TrimSpace(t.NameAR), strings.TrimSpace(t.NameCKB),
		strings.TrimSpace(t.NameKMR), normalizeInterval(t.DefaultInterval), activeInt)
	out, err := scanOne(row)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			return nil, errors.New("type not found")
		}
		return nil, err
	}
	return out, nil
}

// Reorder rewrites display_order to match the given id sequence.
func (s *Store) Reorder(ctx context.Context, orderedIDs []int64) error {
	if len(orderedIDs) == 0 {
		return nil
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	for i, id := range orderedIDs {
		if _, err := tx.Exec(ctx,
			`UPDATE sponsorship_types SET display_order = $2 WHERE id = $1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Delete removes a type. Sponsorships keep their stored type string, so an
// existing record is never orphaned — the type just leaves the picker.
func (s *Store) Delete(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM sponsorship_types WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("type not found")
	}
	return nil
}
