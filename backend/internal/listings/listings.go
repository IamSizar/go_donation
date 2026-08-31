// Package listings hosts simple read-only public endpoints:
//   - partners (status='active')
//   - media posts (status='published')
//   - city directory entries / community (status='approved')
package listings

import (
	"context"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// ----------------- partners -----------------

type Partner struct {
	ID                int64   `json:"id"`
	Name              string  `json:"name"`
	NameAr            *string `json:"name_ar"`
	NameSorani        *string `json:"name_sorani"`
	NameBadini        *string `json:"name_badini"`
	PartnerType       *string `json:"partner_type"`
	ContactPhone      *string `json:"contact_phone"`
	Website           *string `json:"website"`
	Description       *string `json:"description"`
	DescriptionAr     *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	LogoPath          *string `json:"logo_path"`
	Status            string  `json:"status"`
	// #26 — contact + location.
	Email          *string `json:"email"`
	SocialLinks    *string `json:"social_links"`
	Location       *string `json:"location"`
	LocationAr     *string `json:"location_ar"`
	LocationSorani *string `json:"location_sorani"`
	LocationBadini *string `json:"location_badini"`
	// #27 — rating aggregate + the requesting user's own rating (0 if none).
	AvgRating   *float64 `json:"avg_rating"`
	RatingCount int      `json:"rating_count"`
	// "Partner Rating" — the organization-assessed level (1–5), kept
	// separate from the crowd-sourced avg_rating above.
	AdminRating      *float64 `json:"admin_rating"`
	ScoreActivities  *int     `json:"score_activities"`
	ScoreDonations   *int     `json:"score_donations"`
	ScoreCooperation *int     `json:"score_cooperation"`
	ScoreContinuity  *int     `json:"score_continuity"`
	// Free-text justification staff write alongside the assessed level.
	AdminRatingNote string `json:"admin_rating_note"`
	MyRating        int    `json:"my_rating"`
}

// ListPartners returns partners. status="" → no filter. Public default is
// "active"; the admin SPA can pass "" to see every status. q is an optional
// free-text search across name/name_ar/partner_type.
func (s *Store) ListPartners(ctx context.Context, status, q string, limit int, userID int64) ([]Partner, error) {
	limit = clampLimit(limit)
	args := []any{}
	where := []string{}
	if status != "" {
		args = append(args, status)
		where = append(where, "status = $"+itoa(len(args)))
	}
	if q = strings.TrimSpace(q); q != "" {
		args = append(args, "%"+q+"%")
		idx := itoa(len(args))
		where = append(where, "(name ILIKE $"+idx+" OR name_ar ILIKE $"+idx+" OR partner_type ILIKE $"+idx+")")
	}
	whereSQL := ""
	if len(where) > 0 {
		whereSQL = " WHERE " + strings.Join(where, " AND ")
	}
	// #27 — my_rating bound as the last param (0 = anonymous → no rating).
	uidIdx := itoa(len(args) + 1)
	args = append(args, userID)
	sql := `SELECT p.id, p.name, p.name_ar, p.name_sorani, p.name_badini,
	               p.partner_type, p.contact_phone, p.website,
	               p.description, p.description_ar, p.description_sorani, p.description_badini,
	               p.logo_path, p.status,
	               p.email, p.social_links,
	               p.location, p.location_ar, p.location_sorani, p.location_badini,
	               p.avg_rating::float8, p.rating_count,
	               p.admin_rating::float8, p.score_activities, p.score_donations,
	               p.score_cooperation, p.score_continuity, p.admin_rating_note,
	               COALESCE((SELECT stars FROM partner_ratings pr
	                          WHERE pr.partner_id = p.id AND pr.user_id = $` + uidIdx + `), 0)
	          FROM partners p` + whereSQL + ` ORDER BY p.name ASC LIMIT ` + itoa(limit)

	rows, err := s.Pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Partner{}
	for rows.Next() {
		var p Partner
		if err := rows.Scan(
			&p.ID, &p.Name, &p.NameAr, &p.NameSorani, &p.NameBadini,
			&p.PartnerType, &p.ContactPhone, &p.Website,
			&p.Description, &p.DescriptionAr, &p.DescriptionSorani, &p.DescriptionBadini,
			&p.LogoPath, &p.Status,
			&p.Email, &p.SocialLinks,
			&p.Location, &p.LocationAr, &p.LocationSorani, &p.LocationBadini,
			// Order mirrors the SELECT: avg_rating, rating_count, then the
			// admin-assessed block, then the my_rating subquery last.
			&p.AvgRating, &p.RatingCount,
			&p.AdminRating, &p.ScoreActivities, &p.ScoreDonations,
			&p.ScoreCooperation, &p.ScoreContinuity, &p.AdminRatingNote,
			&p.MyRating,
		); err != nil {
			return nil, err
		}
		items = append(items, p)
	}
	return items, rows.Err()
}

// PartnerActivity is one activity carried out with a partner, for the
// Partner Page's "history of activities or initiatives implemented in
// cooperation with the partner".
type PartnerActivity struct {
	ID           int64   `json:"id"`
	Title        string  `json:"title"`
	TitleAr      *string `json:"title_ar"`
	TitleSorani  *string `json:"title_sorani"`
	TitleBadini  *string `json:"title_badini"`
	MediaURL     *string `json:"media_url"`
	EventDate    *string `json:"event_date"`
	ActivityCode string  `json:"activity_code"`
	CategorySlug *string `json:"category_slug"`
}

// PartnerActivities returns published posts attributed to a partner, newest
// first. Empty (not an error) when the partner has none.
func (s *Store) PartnerActivities(ctx context.Context, partnerID int64, limit int) ([]PartnerActivity, error) {
	if partnerID <= 0 {
		return []PartnerActivity{}, nil
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT id, title, title_ar, title_sorani, title_badini,
		        media_url, to_char(event_date, 'YYYY-MM-DD'),
		        activity_code, category_slug
		   FROM media_posts
		  WHERE partner_id = $1 AND status = 'published'
		  ORDER BY COALESCE(event_date, created_at::date) DESC, id DESC
		  LIMIT $2`, partnerID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []PartnerActivity{}
	for rows.Next() {
		var a PartnerActivity
		if err := rows.Scan(&a.ID, &a.Title, &a.TitleAr, &a.TitleSorani, &a.TitleBadini,
			&a.MediaURL, &a.EventDate, &a.ActivityCode, &a.CategorySlug); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// ----------------- media posts -----------------

type MediaPost struct {
	ID          int64      `json:"id"`
	Title       string     `json:"title"`
	TitleAr     *string    `json:"title_ar"`
	TitleSorani *string    `json:"title_sorani"`
	TitleBadini *string    `json:"title_badini"`
	Body        *string    `json:"body"`
	BodyAr      *string    `json:"body_ar"`
	BodySorani  *string    `json:"body_sorani"`
	BodyBadini  *string    `json:"body_badini"`
	PostType    string     `json:"post_type"`
	MediaURL    *string    `json:"media_url"`
	LinkURL     *string    `json:"link_url"`
	EventDate   *time.Time `json:"event_date"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	// #22 — "Our Work" category tag (nullable; matches a media_categories.slug).
	CategorySlug *string `json:"category_slug"`
	// "Post Information" — Activity Code identifying the post + its category.
	ActivityCode string `json:"activity_code"`
	// #23 — 4-language location + media gallery.
	Location       *string  `json:"location"`
	LocationAr     *string  `json:"location_ar"`
	LocationSorani *string  `json:"location_sorani"`
	LocationBadini *string  `json:"location_badini"`
	Gallery        []string `json:"gallery"`
	// #24 — engagement counts + whether the requesting user liked this post.
	LikeCount    int  `json:"like_count"`
	CommentCount int  `json:"comment_count"`
	ShareCount   int  `json:"share_count"`
	LikedByMe    bool `json:"liked_by_me"`
	// "Save for later" (migration 092) — same shape as LikedByMe so the app
	// renders the bookmark in the right state straight from the list.
	SavedByMe bool `json:"saved_by_me"`
}

// parsePostTypes splits a `?type=` value into post_type names. It accepts a
// single name ("activity") or a comma-separated list ("activity,news"), and
// drops blanks so a trailing comma or "a,,b" cannot produce an empty name that
// would match no row and silently empty the feed. An empty result means "no
// type filter" and leaves the caller's default in charge.
func parsePostTypes(raw string) []string {
	out := []string{}
	for _, part := range strings.Split(raw, ",") {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}

// ListMediaPosts returns media posts. status="" → no filter. Public default is
// "published". q is an optional free-text search across title/title_ar/body.
// savedOnly narrows the list to posts this user saved — the query behind the
// app's "Saved" screen. Ignored for an anonymous caller, who has none.
func (s *Store) ListMediaPosts(ctx context.Context, status, postType, q string, limit int, userID int64, savedOnly bool) ([]MediaPost, error) {
	limit = clampLimit(limit)
	args := []any{}
	where := []string{}
	if status != "" {
		args = append(args, status)
		where = append(where, "status = $"+itoa(len(args)))
	}
	// `?type=` accepts one post_type or a comma-separated list ("activity,news"),
	// so a screen scoped to a subset of the feed — the Events hub shows activity
	// posts and news together — asks for exactly that subset in one round trip
	// instead of over-fetching and filtering in the client.
	if types := parsePostTypes(postType); len(types) > 0 {
		args = append(args, types)
		where = append(where, "post_type = ANY($"+itoa(len(args))+")")
	} else {
		// No explicit type → the general news/activities feed. Keep
		// 'marriage' posts out of it; they're only shown when the marriage
		// screen asks for them with ?type=marriage.
		where = append(where, "post_type <> 'marriage'")
	}
	if q = strings.TrimSpace(q); q != "" {
		args = append(args, "%"+q+"%")
		idx := itoa(len(args))
		where = append(where, "(title ILIKE $"+idx+" OR title_ar ILIKE $"+idx+" OR body ILIKE $"+idx+")")
	}
	if savedOnly && userID > 0 {
		args = append(args, userID)
		where = append(where, "id IN (SELECT item_id FROM saved_items WHERE item_type = 'media_post' AND user_id = $"+itoa(len(args))+")")
	}
	whereSQL := ""
	if len(where) > 0 {
		whereSQL = " WHERE " + strings.Join(where, " AND ")
	}
	// #24 — engagement counts + liked_by_me. userID is bound as the last param
	// (0 = anonymous → liked_by_me is always false). The WHERE clauses use
	// unqualified column names, which still resolve against the sole `m` table.
	uidIdx := itoa(len(args) + 1)
	args = append(args, userID)
	sql := `SELECT m.id, m.title, m.title_ar, m.title_sorani, m.title_badini,
	               m.body, m.body_ar, m.body_sorani, m.body_badini,
	               m.post_type, m.media_url, m.link_url, m.event_date, m.status, m.created_at,
	               m.category_slug, m.activity_code,
	               m.location, m.location_ar, m.location_sorani, m.location_badini,
	               COALESCE(m.gallery, '{}'),
	               (SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = m.id),
	               (SELECT COUNT(*) FROM post_comments pc WHERE pc.post_id = m.id AND pc.status = 'approved'),
	               m.share_count,
	               EXISTS(SELECT 1 FROM post_likes plm WHERE plm.post_id = m.id AND plm.user_id = $` + uidIdx + `),
	               EXISTS(SELECT 1 FROM saved_items sv WHERE sv.item_type = 'media_post'
	                        AND sv.item_id = m.id AND sv.user_id = $` + uidIdx + `)
	          FROM media_posts m` + whereSQL + `
	         ORDER BY COALESCE(m.event_date, m.created_at::date) DESC, m.id DESC
	         LIMIT ` + itoa(limit)

	rows, err := s.Pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []MediaPost{}
	for rows.Next() {
		var m MediaPost
		if err := rows.Scan(
			&m.ID, &m.Title, &m.TitleAr, &m.TitleSorani, &m.TitleBadini,
			&m.Body, &m.BodyAr, &m.BodySorani, &m.BodyBadini,
			&m.PostType, &m.MediaURL, &m.LinkURL, &m.EventDate, &m.Status, &m.CreatedAt,
			&m.CategorySlug, &m.ActivityCode,
			&m.Location, &m.LocationAr, &m.LocationSorani, &m.LocationBadini,
			&m.Gallery,
			&m.LikeCount, &m.CommentCount, &m.ShareCount, &m.LikedByMe, &m.SavedByMe,
		); err != nil {
			return nil, err
		}
		items = append(items, m)
	}
	return items, rows.Err()
}

// ----------------- city directory / community -----------------

type Community struct {
	ID                int64   `json:"id"`
	Name              string  `json:"name"`
	NameAr            *string `json:"name_ar"`
	NameSorani        *string `json:"name_sorani"`
	NameBadini        *string `json:"name_badini"`
	Category          string  `json:"category"`
	City              *string `json:"city"`
	Address           *string `json:"address"`
	Phone             *string `json:"phone"`
	Email             *string `json:"email"`
	Website           *string `json:"website"`
	Description       *string `json:"description"`
	DescriptionAr     *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	Latitude          *string `json:"latitude"`
	Longitude         *string `json:"longitude"`
	// #29 — City Guide sectors, 4-language opening hours, photo gallery.
	Sectors            []string `json:"sectors"`
	OpeningHours       *string  `json:"opening_hours"`
	OpeningHoursAr     *string  `json:"opening_hours_ar"`
	OpeningHoursSorani *string  `json:"opening_hours_sorani"`
	OpeningHoursBadini *string  `json:"opening_hours_badini"`
	Gallery            []string `json:"gallery"`
	Status             *string  `json:"status,omitempty"`
	// #48 — 'approx' (coords snapped to ~500m in the public API) or 'exact'.
	ApproxLocation string `json:"approx_location"`
	// Note #19 — mandatory classification: 'government' or 'private'.
	SectorType string `json:"sector_type"`
	// "Social media links, including Facebook, Instagram, and website" — the
	// website already had its own column; this holds the rest (migration 100).
	SocialLinks *string `json:"social_links"`
	// Machine-readable companion to the free-text opening_hours, so the app can
	// show Open Now / Closed. Null when nobody has filled it in, which is the
	// signal to show no badge rather than guess.
	Hours *string `json:"hours"`
	// Admin queue only — when the entry was submitted, so the dashboard can
	// show a date + time column. Null on the public listing, which doesn't
	// select it.
	CreatedAt *string `json:"created_at,omitempty"`
}

// ListCommunity returns approved community-directory entries. q searches
// across name, name_ar, address, phone, and category. sector, when set,
// keeps only places tagged with that sector slug (#29).
func (s *Store) ListCommunity(ctx context.Context, category, city, q, sector string, limit int) ([]Community, error) {
	limit = clampLimit(limit)
	args := []any{}
	where := []string{"status = 'approved'"}
	if category = strings.TrimSpace(category); category != "" {
		args = append(args, category)
		where = append(where, "category = $"+itoa(len(args)))
	}
	if city = strings.TrimSpace(city); city != "" {
		args = append(args, city)
		where = append(where, "city = $"+itoa(len(args)))
	}
	if sector = strings.TrimSpace(sector); sector != "" {
		args = append(args, []string{sector})
		where = append(where, "sectors @> $"+itoa(len(args)))
	}
	if q = strings.TrimSpace(q); q != "" {
		args = append(args, "%"+q+"%")
		idx := itoa(len(args))
		where = append(where, "(name ILIKE $"+idx+" OR name_ar ILIKE $"+idx+" OR address ILIKE $"+idx+" OR phone ILIKE $"+idx+" OR category ILIKE $"+idx+")")
	}
	// #48 — snap coords to a ~500m grid for entries flagged approx_location,
	// so exact coordinates never reach app users.
	sql := `SELECT id, name, name_ar, name_sorani, name_badini,
	               category, city, address, phone, email, website,
	               description, description_ar, description_sorani, description_badini,
	               CASE WHEN approx_location = 1 THEN (ROUND(latitude  / 0.005) * 0.005)::text ELSE latitude::text  END,
	               CASE WHEN approx_location = 1 THEN (ROUND(longitude / 0.005) * 0.005)::text ELSE longitude::text END,
	               sectors, opening_hours, opening_hours_ar, opening_hours_sorani, opening_hours_badini,
	               gallery, CASE WHEN approx_location = 1 THEN 'approx' ELSE 'exact' END, sector_type,
	               social_links, hours::text
	          FROM city_directory_entries
	         WHERE ` + strings.Join(where, " AND ") + `
	         ORDER BY category ASC, name ASC
	         LIMIT ` + itoa(limit)

	rows, err := s.Pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Community{}
	for rows.Next() {
		var c Community
		if err := rows.Scan(
			&c.ID, &c.Name, &c.NameAr, &c.NameSorani, &c.NameBadini,
			&c.Category, &c.City, &c.Address, &c.Phone, &c.Email, &c.Website,
			&c.Description, &c.DescriptionAr, &c.DescriptionSorani, &c.DescriptionBadini,
			&c.Latitude, &c.Longitude,
			&c.Sectors, &c.OpeningHours, &c.OpeningHoursAr, &c.OpeningHoursSorani, &c.OpeningHoursBadini,
			&c.Gallery, &c.ApproxLocation, &c.SectorType,
			&c.SocialLinks, &c.Hours,
		); err != nil {
			return nil, err
		}
		if c.Sectors == nil {
			c.Sectors = []string{}
		}
		if c.Gallery == nil {
			c.Gallery = []string{}
		}
		items = append(items, c)
	}
	return items, rows.Err()
}

// ListCommunityAdmin returns directory entries for the admin queue (#30),
// optionally filtered by status (empty = all statuses, incl. pending).
func (s *Store) ListCommunityAdmin(ctx context.Context, status string, limit int) ([]Community, error) {
	limit = clampLimit(limit)
	args := []any{}
	where := []string{"1=1"}
	if status = strings.TrimSpace(status); status != "" {
		args = append(args, status)
		where = append(where, "status = $"+itoa(len(args)))
	}
	// Admin sees EXACT coordinates + the approx_location flag (they edit it).
	sql := `SELECT id, name, name_ar, name_sorani, name_badini,
	               category, city, address, phone, email, website,
	               description, description_ar, description_sorani, description_badini,
	               latitude::text, longitude::text,
	               sectors, opening_hours, opening_hours_ar, opening_hours_sorani, opening_hours_badini,
	               gallery, status, CASE WHEN approx_location = 1 THEN 'approx' ELSE 'exact' END, sector_type,
	               social_links, hours::text,
	               to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS')
	          FROM city_directory_entries
	         WHERE ` + strings.Join(where, " AND ") + `
	         ORDER BY (status = 'pending') DESC, created_at DESC
	         LIMIT ` + itoa(limit)
	rows, err := s.Pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Community{}
	for rows.Next() {
		var c Community
		if err := rows.Scan(
			&c.ID, &c.Name, &c.NameAr, &c.NameSorani, &c.NameBadini,
			&c.Category, &c.City, &c.Address, &c.Phone, &c.Email, &c.Website,
			&c.Description, &c.DescriptionAr, &c.DescriptionSorani, &c.DescriptionBadini,
			&c.Latitude, &c.Longitude,
			&c.Sectors, &c.OpeningHours, &c.OpeningHoursAr, &c.OpeningHoursSorani, &c.OpeningHoursBadini,
			&c.Gallery, &c.Status, &c.ApproxLocation, &c.SectorType,
			&c.SocialLinks, &c.Hours,
			&c.CreatedAt,
		); err != nil {
			return nil, err
		}
		if c.Sectors == nil {
			c.Sectors = []string{}
		}
		if c.Gallery == nil {
			c.Gallery = []string{}
		}
		items = append(items, c)
	}
	return items, rows.Err()
}

// CommunitySubmission is a user-submitted place awaiting admin approval (#30).
type CommunitySubmission struct {
	Name         string
	NameAr       string
	NameSorani   string
	NameBadini   string
	Category     string
	City         string
	Address      string
	Phone        string
	Website      string
	Latitude     string
	Longitude    string
	Sectors      []string
	OpeningHours string
	SubmittedBy  *int64
}

// SubmitCommunity inserts a user-submitted place with status='pending' (#30),
// so it stays out of the public directory until an admin approves it.
func (s *Store) SubmitCommunity(ctx context.Context, sub CommunitySubmission) (int64, error) {
	if sub.Sectors == nil {
		sub.Sectors = []string{}
	}
	nilIfEmpty := func(v string) any {
		if strings.TrimSpace(v) == "" {
			return nil
		}
		return v
	}
	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO city_directory_entries
		  (name, name_ar, name_sorani, name_badini, category, city, address, phone, website,
		   latitude, longitude, sectors, opening_hours, status, submitted_by)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'pending',$14)
		RETURNING id`,
		sub.Name, nilIfEmpty(sub.NameAr), nilIfEmpty(sub.NameSorani), nilIfEmpty(sub.NameBadini),
		sub.Category, nilIfEmpty(sub.City), nilIfEmpty(sub.Address), nilIfEmpty(sub.Phone),
		nilIfEmpty(sub.Website), nilIfEmpty(sub.Latitude), nilIfEmpty(sub.Longitude),
		sub.Sectors, nilIfEmpty(sub.OpeningHours), sub.SubmittedBy,
	).Scan(&id)
	return id, err
}

// ----------------- helpers -----------------

func clampLimit(l int) int {
	if l <= 0 || l > 100 {
		return 50
	}
	return l
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
