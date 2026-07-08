// Package search backs the app-wide global search box (#33): one query fanned
// out across the main public content tables, returning a flat, typed result
// list the app groups and renders. Only public rows are matched (each table's
// public status filter is applied).
package search

import (
	"context"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Result is one hit. Type is one of: campaign | media | product | partner |
// place. The 4 name fields let the app localize the title via its usual chain.
type Result struct {
	Type       string  `json:"type"`
	ID         int64   `json:"id"`
	Name       string  `json:"name"`
	NameAr     *string `json:"name_ar"`
	NameSorani *string `json:"name_sorani"`
	NameBadini *string `json:"name_badini"`
}

// each source: a type tag + a query selecting (id, name, name_ar, name_sorani,
// name_badini) for public rows whose localized title matches. $1 = ILIKE term.
type source struct {
	typ string
	sql string
}

var sources = []source{
	{"campaign", `SELECT id, title, title_ar, title_sorani, title_badini FROM campaigns
	   WHERE status = 'active'
	     AND (title ILIKE $1 OR title_ar ILIKE $1 OR title_sorani ILIKE $1 OR title_badini ILIKE $1)`},
	{"media", `SELECT id, title, title_ar, title_sorani, title_badini FROM media_posts
	   WHERE status = 'published'
	     AND (title ILIKE $1 OR title_ar ILIKE $1 OR title_sorani ILIKE $1 OR title_badini ILIKE $1)`},
	{"product", `SELECT id, name, name_ar, name_sorani, name_badini FROM marketplace_products
	   WHERE status = 'approved'
	     AND (name ILIKE $1 OR name_ar ILIKE $1 OR name_sorani ILIKE $1 OR name_badini ILIKE $1)`},
	{"partner", `SELECT id, name, name_ar, name_sorani, name_badini FROM partners
	   WHERE status = 'active'
	     AND (name ILIKE $1 OR name_ar ILIKE $1 OR name_sorani ILIKE $1 OR name_badini ILIKE $1)`},
	{"place", `SELECT id, name, name_ar, name_sorani, name_badini FROM city_directory_entries
	   WHERE status = 'approved'
	     AND (name ILIKE $1 OR name_ar ILIKE $1 OR name_sorani ILIKE $1 OR name_badini ILIKE $1)`},
}

// Search fans the query across every source. perType caps rows per source so
// one busy table can't crowd out the rest.
func (s *Store) Search(ctx context.Context, q string, perType int) ([]Result, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return []Result{}, nil
	}
	if perType <= 0 || perType > 50 {
		perType = 8
	}
	like := "%" + q + "%"
	out := []Result{}
	for _, src := range sources {
		rows, err := s.Pool.Query(ctx, src.sql+" ORDER BY id DESC LIMIT $2", like, perType)
		if err != nil {
			return nil, err
		}
		for rows.Next() {
			r := Result{Type: src.typ}
			if err := rows.Scan(&r.ID, &r.Name, &r.NameAr, &r.NameSorani, &r.NameBadini); err != nil {
				rows.Close()
				return nil, err
			}
			out = append(out, r)
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return nil, err
		}
		rows.Close()
	}
	return out, nil
}
