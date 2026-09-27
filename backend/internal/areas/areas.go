// Package areas backs the dashboard-managed location tree under the fixed 18
// governorates (migration 136): cities, their districts (أقضية) and those
// districts' sub-districts (نواحي). Same shape and conventions as the
// districts CMS (4-language names, display order, active flag).
package areas

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	LevelCity        = "city"
	LevelDistrict    = "district"
	LevelSubdistrict = "subdistrict"
)

// Governorates is the app's fixed list (humanitarian/lib/data/
// iraq_governorates.dart). An area can only hang off one of these keys.
var Governorates = []string{
	"Baghdad", "Basra", "Nineveh", "Erbil", "Sulaymaniyah", "Duhok", "Kirkuk",
	"Anbar", "Najaf", "Karbala", "Wasit", "Babil", "Diyala", "Salah al-Din",
	"Dhi Qar", "Maysan", "Muthanna", "Al-Qadisiyyah",
}

func IsGovernorate(g string) bool {
	for _, x := range Governorates {
		if x == g {
			return true
		}
	}
	return false
}

// parentLevel is the level an area of `level` must hang off ("" = none).
func parentLevel(level string) string {
	switch level {
	case LevelDistrict:
		return LevelCity
	case LevelSubdistrict:
		return LevelDistrict
	}
	return ""
}

var (
	ErrNotFound     = errors.New("area not found")
	ErrHasChildren  = errors.New("area still has districts or sub-districts under it")
	ErrDuplicate    = errors.New("an area with that Arabic name already exists here")
	ErrBadGov       = errors.New("unknown governorate")
	ErrBadLevel     = errors.New("level must be city, district or subdistrict")
	ErrBadParent    = errors.New("parent must be a matching area in the same governorate")
	ErrNameRequired = errors.New("an Arabic or English name is required")
)

type Area struct {
	ID           int64  `json:"id"`
	Governorate  string `json:"governorate"`
	ParentID     *int64 `json:"parent_id"`
	Level        string `json:"level"`
	NameEN       string `json:"name_en"`
	NameAR       string `json:"name_ar"`
	NameCKB      string `json:"name_ckb"`
	NameKMR      string `json:"name_kmr"`
	DisplayOrder int    `json:"display_order"`
	Active       bool   `json:"active"`
	// Children counts direct sub-areas (admin list only), so the manager can
	// say why a delete is refused before the operator tries it.
	Children int `json:"children"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

const cols = `a.id, a.governorate, a.parent_id, a.level, a.name_en, a.name_ar, a.name_ckb, a.name_kmr,
	a.display_order, (a.active = 1),
	(SELECT COUNT(*) FROM location_areas c WHERE c.parent_id = a.id)`

func scan(row pgx.Row, a *Area) error {
	return row.Scan(&a.ID, &a.Governorate, &a.ParentID, &a.Level, &a.NameEN, &a.NameAR, &a.NameCKB, &a.NameKMR,
		&a.DisplayOrder, &a.Active, &a.Children)
}

// List returns every area of one governorate, ordered level → display order.
// activeOnly (the app) also drops anything under a hidden parent, so hiding a
// city hides its whole branch.
func (s *Store) List(ctx context.Context, governorate string, activeOnly bool) ([]Area, error) {
	where := "a.governorate = $1"
	if activeOnly {
		where += ` AND a.active = 1
		   AND (a.parent_id IS NULL OR EXISTS (
		        SELECT 1 FROM location_areas p WHERE p.id = a.parent_id AND p.active = 1
		          AND (p.parent_id IS NULL OR EXISTS (
		               SELECT 1 FROM location_areas g WHERE g.id = p.parent_id AND g.active = 1))))`
	}
	rows, err := s.Pool.Query(ctx, `SELECT `+cols+` FROM location_areas a WHERE `+where+`
		ORDER BY CASE a.level WHEN 'city' THEN 0 WHEN 'district' THEN 1 ELSE 2 END,
		         a.display_order, a.id`, governorate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Area{}
	for rows.Next() {
		var a Area
		if err := scan(rows, &a); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (s *Store) get(ctx context.Context, id int64) (*Area, error) {
	var a Area
	err := scan(s.Pool.QueryRow(ctx, `SELECT `+cols+` FROM location_areas a WHERE a.id = $1`, id), &a)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &a, nil
}

func trimNames(a *Area) {
	a.NameEN = strings.TrimSpace(a.NameEN)
	a.NameAR = strings.TrimSpace(a.NameAR)
	a.NameCKB = strings.TrimSpace(a.NameCKB)
	a.NameKMR = strings.TrimSpace(a.NameKMR)
}

func isDuplicate(err error) bool {
	return err != nil && (strings.Contains(err.Error(), "23505") || strings.Contains(strings.ToLower(err.Error()), "duplicate"))
}

// Add inserts an area at the end of its siblings. The governorate and level
// are validated, and a parent must be the level directly above in the same
// governorate — a sub-district cannot hang straight off a city.
func (s *Store) Add(ctx context.Context, a Area, actorID *int64) (*Area, error) {
	trimNames(&a)
	a.Governorate = strings.TrimSpace(a.Governorate)
	if !IsGovernorate(a.Governorate) {
		return nil, ErrBadGov
	}
	if a.Level != LevelCity && a.Level != LevelDistrict && a.Level != LevelSubdistrict {
		return nil, ErrBadLevel
	}
	if a.NameAR == "" && a.NameEN == "" {
		return nil, ErrNameRequired
	}
	want := parentLevel(a.Level)
	if want == "" {
		a.ParentID = nil
	} else {
		if a.ParentID == nil {
			return nil, ErrBadParent
		}
		p, err := s.get(ctx, *a.ParentID)
		if err != nil || p.Level != want || p.Governorate != a.Governorate {
			return nil, ErrBadParent
		}
	}
	var id int64
	err := s.Pool.QueryRow(ctx,
		`INSERT INTO location_areas (governorate, parent_id, level, name_en, name_ar, name_ckb, name_kmr, display_order, created_by)
		 VALUES ($1::varchar, $2::int, $3::varchar, $4, $5, $6, $7,
		         COALESCE((SELECT MAX(display_order) FROM location_areas
		                    WHERE governorate = $1::varchar AND level = $3::varchar
		                      AND parent_id IS NOT DISTINCT FROM $2::int), 0) + 1,
		         $8)
		 RETURNING id`,
		a.Governorate, a.ParentID, a.Level, a.NameEN, a.NameAR, a.NameCKB, a.NameKMR, actorID,
	).Scan(&id)
	if isDuplicate(err) {
		return nil, ErrDuplicate
	}
	if err != nil {
		return nil, err
	}
	return s.get(ctx, id)
}

// Update edits names and the active flag. Governorate, level and parent are
// fixed: moving a place is a delete + add, same rule as the districts CMS.
func (s *Store) Update(ctx context.Context, id int64, a Area) (*Area, error) {
	trimNames(&a)
	if a.NameAR == "" && a.NameEN == "" {
		return nil, ErrNameRequired
	}
	active := 0
	if a.Active {
		active = 1
	}
	ct, err := s.Pool.Exec(ctx,
		`UPDATE location_areas SET name_en = $2, name_ar = $3, name_ckb = $4, name_kmr = $5, active = $6
		  WHERE id = $1`, id, a.NameEN, a.NameAR, a.NameCKB, a.NameKMR, active)
	if isDuplicate(err) {
		return nil, ErrDuplicate
	}
	if err != nil {
		return nil, err
	}
	if ct.RowsAffected() == 0 {
		return nil, ErrNotFound
	}
	return s.get(ctx, id)
}

// Reorder rewrites display_order for one sibling list (first id → 1).
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
		if _, err := tx.Exec(ctx, `UPDATE location_areas SET display_order = $2 WHERE id = $1`, id, i+1); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// CanDelete refuses an area that still has children: deleting a city must not
// silently take its districts and sub-districts with it (and the Trash could
// only give back the city).
func (s *Store) CanDelete(ctx context.Context, id int64) error {
	a, err := s.get(ctx, id)
	if err != nil {
		return err
	}
	if a.Children > 0 {
		return ErrHasChildren
	}
	return nil
}
