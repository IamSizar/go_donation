// Package content is a tiny store for editable static pages (Terms & Conditions
// now; About/Contact later). One row per slug in app_content, title+body in the
// four supported locales. Mirrors the guest.Store style (thin pgxpool wrapper).
package content

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned by Get when no row exists for the slug.
var ErrNotFound = errors.New("content not found")

// Content is a single editable page in all four locales.
type Content struct {
	Slug     string `json:"slug"`
	TitleEn  string `json:"title_en"`
	TitleAr  string `json:"title_ar"`
	TitleCkb string `json:"title_ckb"`
	TitleKmr string `json:"title_kmr"`
	BodyEn   string `json:"body_en"`
	BodyAr   string `json:"body_ar"`
	BodyCkb  string `json:"body_ckb"`
	BodyKmr  string `json:"body_kmr"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Get returns the content for a slug, or ErrNotFound.
func (s *Store) Get(ctx context.Context, slug string) (Content, error) {
	var c Content
	err := s.Pool.QueryRow(ctx,
		`SELECT slug, title_en, title_ar, title_ckb, title_kmr,
		        body_en, body_ar, body_ckb, body_kmr
		   FROM app_content WHERE slug = $1`, slug,
	).Scan(&c.Slug, &c.TitleEn, &c.TitleAr, &c.TitleCkb, &c.TitleKmr,
		&c.BodyEn, &c.BodyAr, &c.BodyCkb, &c.BodyKmr)
	if errors.Is(err, pgx.ErrNoRows) {
		return Content{}, ErrNotFound
	}
	if err != nil {
		return Content{}, err
	}
	return c, nil
}

// Upsert creates or updates the content for a slug, stamping the editor.
func (s *Store) Upsert(ctx context.Context, c Content, updatedBy int64) error {
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO app_content
		   (slug, title_en, title_ar, title_ckb, title_kmr,
		    body_en, body_ar, body_ckb, body_kmr, updated_at, updated_by)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9, NOW(), $10)
		 ON CONFLICT (slug) DO UPDATE SET
		    title_en = EXCLUDED.title_en, title_ar = EXCLUDED.title_ar,
		    title_ckb = EXCLUDED.title_ckb, title_kmr = EXCLUDED.title_kmr,
		    body_en = EXCLUDED.body_en, body_ar = EXCLUDED.body_ar,
		    body_ckb = EXCLUDED.body_ckb, body_kmr = EXCLUDED.body_kmr,
		    updated_at = NOW(), updated_by = EXCLUDED.updated_by`,
		c.Slug, c.TitleEn, c.TitleAr, c.TitleCkb, c.TitleKmr,
		c.BodyEn, c.BodyAr, c.BodyCkb, c.BodyKmr, updatedBy)
	return err
}
