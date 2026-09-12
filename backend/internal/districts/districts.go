// Package districts backs the admin-managed district/neighborhood list
// (OPOS #25271): the registration form's Nineveh-specific "District" and
// "Neighborhood" pickers, previously a hardcoded English-only Dart const
// list with no way to add a missing entry short of a code deploy. Mirrors
// the citycategories CMS pattern exactly, scoped by group_key instead of
// sector_slug (migration 120).
package districts

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// District is one district/neighborhood entry with its 4-language display
// names, scoped to a group (which picker it belongs to).
type District struct {
	ID   int64  `json:"id"`
	Slug string `json:"slug"`
	// Which picker this entry belongs to: nineveh_district,
	// nineveh_neighborhood_left, or nineveh_neighborhood_right.
	GroupKey     string `json:"group_key"`
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
// runs collapsed to a single underscore.
func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = slugStripRE.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

// List returns districts in admin-defined display order (id tiebreak),
// optionally filtered to one group. When activeOnly, only active rows (used
// by the public app picker).
func (s *Store) List(ctx context.Context, groupKey string, activeOnly bool) ([]District, error) {
	where := []string{}
	args := []any{}
	if groupKey != "" {
		args = append(args, groupKey)
		where = append(where, "group_key = $1")
	}
	if activeOnly {
		where = append(where, "active = 1")
	}
	clause := ""
	if len(where) > 0 {
		clause = " WHERE " + strings.Join(where, " AND ")
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT id, slug, group_key, name_en, name_ar, name_ckb, name_kmr, display_order, (active = 1)
		   FROM districts`+clause+`
		  ORDER BY group_key, display_order, id`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []District{}
	for rows.Next() {
		var d District
		if err := rows.Scan(&d.ID, &d.Slug, &d.GroupKey, &d.NameEN, &d.NameAR, &d.NameCKB, &d.NameKMR,
			&d.DisplayOrder, &d.Active); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// Add inserts a new district, deriving the slug from the English name (or an
// explicit slug). New districts are active. Returns the stored row.
func (s *Store) Add(ctx context.Context, d District, actorID *int64) (*District, error) {
	d.NameEN = strings.TrimSpace(d.NameEN)
	if d.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	d.GroupKey = strings.TrimSpace(d.GroupKey)
	if d.GroupKey == "" {
		return nil, errors.New("group is required")
	}
	key := slugify(d.Slug)
	if key == "" {
		key = slugify(d.NameEN)
	}
	if key == "" {
		return nil, errors.New("could not derive a district key")
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO districts (slug, group_key, name_en, name_ar, name_ckb, name_kmr, active, created_by)
		 VALUES ($1, $2, $3, $4, $5, $6, 1, $7)
		 RETURNING id, display_order, (active = 1)`,
		key, d.GroupKey, d.NameEN, strings.TrimSpace(d.NameAR),
		strings.TrimSpace(d.NameCKB), strings.TrimSpace(d.NameKMR), actorID,
	).Scan(&id, &d.DisplayOrder, &d.Active)
	if err != nil {
		if strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, errors.New("a district with that name already exists in this group")
		}
		return nil, err
	}
	d.ID = id
	d.Slug = key
	return &d, nil
}

// Update edits a district's names and active flag. The slug and group are
// immutable — moving a place between groups is a delete+add, not an edit.
func (s *Store) Update(ctx context.Context, id int64, d District) (*District, error) {
	d.NameEN = strings.TrimSpace(d.NameEN)
	if d.NameEN == "" {
		return nil, errors.New("English name is required")
	}
	activeInt := 0
	if d.Active {
		activeInt = 1
	}
	var out District
	err := s.Pool.QueryRow(ctx,
		`UPDATE districts
		    SET name_en = $2, name_ar = $3, name_ckb = $4, name_kmr = $5, active = $6
		  WHERE id = $1
		  RETURNING id, slug, group_key, name_en, name_ar, name_ckb, name_kmr, display_order, (active = 1)`,
		id, d.NameEN, strings.TrimSpace(d.NameAR),
		strings.TrimSpace(d.NameCKB), strings.TrimSpace(d.NameKMR), activeInt,
	).Scan(&out.ID, &out.Slug, &out.GroupKey, &out.NameEN, &out.NameAR, &out.NameCKB, &out.NameKMR,
		&out.DisplayOrder, &out.Active)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			return nil, errors.New("district not found")
		}
		return nil, err
	}
	return &out, nil
}

// Reorder rewrites display_order to match the given id sequence (first id →
// 1, etc.) in a single transaction. Scoped implicitly: callers pass one
// group's ids at a time, since the manager UI reorders one picker's list.
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
			`UPDATE districts SET display_order = $2 WHERE id = $1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// Delete removes a district row outright. Existing registrations keep
// whatever string they already submitted (the picker's value, not a live
// reference) — the district simply drops out of future pickers.
func (s *Store) Delete(ctx context.Context, id int64) error {
	ct, err := s.Pool.Exec(ctx, `DELETE FROM districts WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("district not found")
	}
	return nil
}
