// Sub-sections of an editable content page (K12).
//
// WHY THIS FILE EXISTS
// `app_content` stores one title and one body per locale per page, which is
// all "من نحن" ever was: a single free-text blob. The client asked for it to
// carry THREE NAMED sub-sections — about the app, about the organization,
// about its goals — and to stay EXTENDABLE, so a fourth needs no code change.
//
// Migration 111 adds `app_content_sections` (slug, display_order, title+body
// per locale). This file is the repository half: read a page's sub-sections,
// and replace the whole list in one transaction.
//
// THE COMPOSITION RULE — read this before changing anything here.
// The Flutter screen renders `app_content.body_*` and nothing else, and this
// repo cannot change it. So ReplaceSections writes the sub-sections AND
// composes them back into `body_*`, in order, inside the same transaction.
// That is what makes a split About Us visible in the app that is already
// installed, while `sections` in the same API response is what a future app
// build renders as separately-titled blocks. A page with NO sub-sections is
// left alone: it is a plain blob page, exactly as before K12.
package content

import (
	"context"
	"fmt"
	"strings"
)

// MaxSections bounds one page's sub-section list. K12 asks for three and for
// room to grow; this is a trust-boundary guard against an unbounded payload,
// not a product limit, and is deliberately far above any plausible page.
const MaxSections = 50

// Section is one named, ordered sub-section of a content page, in all four
// supported locales.
//
// An EMPTY title is legal and meaningful: it is an untitled block of prose,
// which is what migration 111's backfill made every pre-K12 page — the page
// heading is `app_content.title_*`, so repeating it here would double it.
type Section struct {
	ID int64 `json:"id"`
	// Order is the stored sort key. It is REPORTED on read and IGNORED on
	// write: ReplaceSections numbers the list from the array it is given, so
	// the order the dashboard shows is the order it saves, with no chance of
	// two sub-sections claiming the same slot.
	Order    int    `json:"display_order"`
	TitleEn  string `json:"title_en"`
	TitleAr  string `json:"title_ar"`
	TitleCkb string `json:"title_ckb"`
	TitleKmr string `json:"title_kmr"`
	BodyEn   string `json:"body_en"`
	BodyAr   string `json:"body_ar"`
	BodyCkb  string `json:"body_ckb"`
	BodyKmr  string `json:"body_kmr"`
}

// ListSections returns a page's sub-sections in display order.
//
// A page with none returns an empty slice, never nil, so the JSON response
// carries `"sections": []` rather than `null` — the app can then treat "no
// sub-sections" as a plain blob page without a null check.
func (s *Store) ListSections(ctx context.Context, slug string) ([]Section, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT id, display_order,
		        title_en, title_ar, title_ckb, title_kmr,
		        body_en, body_ar, body_ckb, body_kmr
		   FROM app_content_sections
		  WHERE slug = $1
		  ORDER BY display_order, id`, slug)
	if err != nil {
		return nil, fmt.Errorf("listing sections of %q: %w", slug, err)
	}
	defer rows.Close()

	out := []Section{}
	for rows.Next() {
		var sec Section
		if err := rows.Scan(&sec.ID, &sec.Order,
			&sec.TitleEn, &sec.TitleAr, &sec.TitleCkb, &sec.TitleKmr,
			&sec.BodyEn, &sec.BodyAr, &sec.BodyCkb, &sec.BodyKmr); err != nil {
			return nil, fmt.Errorf("scanning section of %q: %w", slug, err)
		}
		out = append(out, sec)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("reading sections of %q: %w", slug, err)
	}
	return out, nil
}

// ReplaceSections replaces a page's whole sub-section list and recomposes the
// legacy `body_*` blob from it, atomically.
//
// Replace-all rather than per-row edits because the dashboard edits the list as
// one form with one Save: reorder, rename, add and remove all arrive together,
// and a partial application of that is a half-rewritten page. Row ids are not
// referenced by anything, so recreating them costs nothing.
//
// `sections` empty is NOT the same as "blank the page": it means the page has
// gone back to being a plain blob, so `body_*` is left exactly as it is and the
// plain body editor takes over again. Composing an empty list into `body_*`
// would silently wipe live text.
func (s *Store) ReplaceSections(ctx context.Context, slug string, sections []Section, updatedBy int64) error {
	if len(sections) > MaxSections {
		return fmt.Errorf("replacing sections of %q: %d sub-sections exceeds the limit of %d",
			slug, len(sections), MaxSections)
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("beginning section transaction for %q: %w", slug, err)
	}
	// Rollback after a successful Commit is a no-op, so this is safe as the
	// single unconditional cleanup path.
	defer func() { _ = tx.Rollback(ctx) }()

	// The FK points at app_content(slug), so a page that is allowed but not yet
	// seeded would reject its own first sub-section. Creating the empty row
	// here is the same upsert the page editor performs, and is a no-op for the
	// eight pages that already exist.
	if _, err := tx.Exec(ctx,
		`INSERT INTO app_content (slug) VALUES ($1) ON CONFLICT (slug) DO NOTHING`,
		slug); err != nil {
		return fmt.Errorf("ensuring content page %q exists: %w", slug, err)
	}

	if _, err := tx.Exec(ctx,
		`DELETE FROM app_content_sections WHERE slug = $1`, slug); err != nil {
		return fmt.Errorf("clearing sections of %q: %w", slug, err)
	}

	for i, sec := range sections {
		if _, err := tx.Exec(ctx,
			`INSERT INTO app_content_sections
			   (slug, display_order,
			    title_en, title_ar, title_ckb, title_kmr,
			    body_en, body_ar, body_ckb, body_kmr,
			    updated_at, updated_by)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, NOW(), $11)`,
			slug, i,
			sec.TitleEn, sec.TitleAr, sec.TitleCkb, sec.TitleKmr,
			sec.BodyEn, sec.BodyAr, sec.BodyCkb, sec.BodyKmr,
			updatedBy); err != nil {
			return fmt.Errorf("inserting sub-section %d of %q: %w", i, slug, err)
		}
	}

	if len(sections) > 0 {
		if _, err := tx.Exec(ctx,
			`UPDATE app_content
			    SET body_en = $2, body_ar = $3, body_ckb = $4, body_kmr = $5,
			        updated_at = NOW(), updated_by = $6
			  WHERE slug = $1`,
			slug,
			composeBody(sections, "en"), composeBody(sections, "ar"),
			composeBody(sections, "ckb"), composeBody(sections, "kmr"),
			updatedBy); err != nil {
			return fmt.Errorf("composing body of %q from its sub-sections: %w", slug, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("committing sections of %q: %w", slug, err)
	}
	return nil
}

// composeBody flattens the ordered sub-sections into the one-blob form the
// installed app renders, for a single locale.
//
// Each sub-section contributes its name then its prose, blank-line separated —
// the shape the page already had, now with headings. A sub-section with
// nothing in THIS locale contributes nothing at all, so a half-translated page
// reads as the parts that exist rather than as a run of empty gaps.
func composeBody(sections []Section, lang string) string {
	parts := make([]string, 0, len(sections)*2)
	for _, sec := range sections {
		title, body := sec.localeText(lang)
		if title = strings.TrimSpace(title); title != "" {
			parts = append(parts, title)
		}
		if body = strings.TrimSpace(body); body != "" {
			parts = append(parts, body)
		}
	}
	return strings.Join(parts, "\n\n")
}

// localeText picks one locale's pair out of a sub-section. Unknown languages
// fall back to English, matching the app's own `_pick` chain.
func (sec Section) localeText(lang string) (title, body string) {
	switch lang {
	case "ar":
		return sec.TitleAr, sec.BodyAr
	case "ckb":
		return sec.TitleCkb, sec.BodyCkb
	case "kmr":
		return sec.TitleKmr, sec.BodyKmr
	default:
		return sec.TitleEn, sec.BodyEn
	}
}
