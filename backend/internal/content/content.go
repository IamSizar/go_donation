// Package content is a tiny store for editable static pages (Terms & Conditions
// now; About/Contact later). One row per slug in app_content, title+body in the
// four supported locales. Mirrors the guest.Store style (thin pgxpool wrapper).
package content

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned by Get when no row exists for the slug.
var ErrNotFound = errors.New("content not found")

// Content is a single editable page in all four locales.
//
// K13 — it also carries the page's own CONTACT DETAILS. They live here rather
// than in a side table because they are one-per-page, and because migration 099
// already gives each section its own row precisely so the marriage service and
// the city guide can publish different numbers from the humanitarian side.
// Every one of them is optional and empty by default: the owner supplies the
// real values from the dashboard.
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

	// ─── Contact details (K13) ──────────────────────────────────────────
	// LogoPath is a path into the same upload store as partners.logo_path.
	LogoPath string `json:"logo_path"`
	// ContactPhone and ContactWhatsApp are separate because the client listed
	// them separately and a WhatsApp line is often not the office number.
	ContactPhone    string `json:"contact_phone"`
	ContactWhatsApp string `json:"contact_whatsapp"`
	ContactEmail    string `json:"contact_email"`
	// SocialLinks is the SAME free-text shape partners (035) and
	// city_directory_entries (100) store — one URL per line, commas tolerated —
	// so the app's existing parser reads it unchanged.
	SocialLinks string `json:"social_links"`
	// The address is prose a human reads, so it is localized like every other
	// text on this table.
	AddressEn  string `json:"address_en"`
	AddressAr  string `json:"address_ar"`
	AddressCkb string `json:"address_ckb"`
	AddressKmr string `json:"address_kmr"`
}

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Get returns the content for a slug, or ErrNotFound.
func (s *Store) Get(ctx context.Context, slug string) (Content, error) {
	var c Content
	err := s.Pool.QueryRow(ctx,
		`SELECT slug, title_en, title_ar, title_ckb, title_kmr,
		        body_en, body_ar, body_ckb, body_kmr,
		        logo_path, contact_phone, contact_whatsapp, contact_email,
		        social_links, address_en, address_ar, address_ckb, address_kmr
		   FROM app_content WHERE slug = $1`, slug,
	).Scan(&c.Slug, &c.TitleEn, &c.TitleAr, &c.TitleCkb, &c.TitleKmr,
		&c.BodyEn, &c.BodyAr, &c.BodyCkb, &c.BodyKmr,
		&c.LogoPath, &c.ContactPhone, &c.ContactWhatsApp, &c.ContactEmail,
		&c.SocialLinks, &c.AddressEn, &c.AddressAr, &c.AddressCkb, &c.AddressKmr)
	if errors.Is(err, pgx.ErrNoRows) {
		return Content{}, ErrNotFound
	}
	if err != nil {
		return Content{}, fmt.Errorf("reading content page %q: %w", slug, err)
	}
	return c, nil
}

// Upsert creates or updates the content for a slug, stamping the editor.
//
// Every column is written from the payload, including the K13 contact fields,
// so the dashboard must send back the whole page it loaded — which it does: the
// editor loads, edits and saves one object. A partial payload would blank the
// fields it omitted.
func (s *Store) Upsert(ctx context.Context, c Content, updatedBy int64) error {
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO app_content
		   (slug, title_en, title_ar, title_ckb, title_kmr,
		    body_en, body_ar, body_ckb, body_kmr,
		    logo_path, contact_phone, contact_whatsapp, contact_email,
		    social_links, address_en, address_ar, address_ckb, address_kmr,
		    updated_at, updated_by)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18, NOW(), $19)
		 ON CONFLICT (slug) DO UPDATE SET
		    title_en = EXCLUDED.title_en, title_ar = EXCLUDED.title_ar,
		    title_ckb = EXCLUDED.title_ckb, title_kmr = EXCLUDED.title_kmr,
		    body_en = EXCLUDED.body_en, body_ar = EXCLUDED.body_ar,
		    body_ckb = EXCLUDED.body_ckb, body_kmr = EXCLUDED.body_kmr,
		    logo_path = EXCLUDED.logo_path,
		    contact_phone = EXCLUDED.contact_phone,
		    contact_whatsapp = EXCLUDED.contact_whatsapp,
		    contact_email = EXCLUDED.contact_email,
		    social_links = EXCLUDED.social_links,
		    address_en = EXCLUDED.address_en, address_ar = EXCLUDED.address_ar,
		    address_ckb = EXCLUDED.address_ckb, address_kmr = EXCLUDED.address_kmr,
		    updated_at = NOW(), updated_by = EXCLUDED.updated_by`,
		c.Slug, c.TitleEn, c.TitleAr, c.TitleCkb, c.TitleKmr,
		c.BodyEn, c.BodyAr, c.BodyCkb, c.BodyKmr,
		c.LogoPath, c.ContactPhone, c.ContactWhatsApp, c.ContactEmail,
		c.SocialLinks, c.AddressEn, c.AddressAr, c.AddressCkb, c.AddressKmr,
		updatedBy)
	if err != nil {
		return fmt.Errorf("saving content page %q: %w", c.Slug, err)
	}
	return nil
}
