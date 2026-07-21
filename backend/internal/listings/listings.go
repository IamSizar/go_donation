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
	MyRating    int      `json:"my_rating"`
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
			&p.AvgRating, &p.RatingCount, &p.MyRating,
		); err != nil {
			return nil, err
		}
		items = append(items, p)
	}
	return items, rows.Err()
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
}

// ListMediaPosts returns media posts. status="" → no filter. Public default is
// "published". q is an optional free-text search across title/title_ar/body.
func (s *Store) ListMediaPosts(ctx context.Context, status, postType, q string, limit int, userID int64) ([]MediaPost, error) {
	limit = clampLimit(limit)
	args := []any{}
	where := []string{}
	if status != "" {
		args = append(args, status)
		where = append(where, "status = $"+itoa(len(args)))
	}
	postType = strings.TrimSpace(postType)
	if postType != "" {
		args = append(args, postType)
		where = append(where, "post_type = $"+itoa(len(args)))
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
	               m.category_slug, m.location, m.location_ar, m.location_sorani, m.location_badini,
	               COALESCE(m.gallery, '{}'),
	               (SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = m.id),
	               (SELECT COUNT(*) FROM post_comments pc WHERE pc.post_id = m.id AND pc.status = 'approved'),
	               m.share_count,
	               EXISTS(SELECT 1 FROM post_likes plm WHERE plm.post_id = m.id AND plm.user_id = $` + uidIdx + `)
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
			&m.CategorySlug, &m.Location, &m.LocationAr, &m.LocationSorani, &m.LocationBadini,
			&m.Gallery,
			&m.LikeCount, &m.CommentCount, &m.ShareCount, &m.LikedByMe,
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
	               gallery, CASE WHEN approx_location = 1 THEN 'approx' ELSE 'exact' END, sector_type
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
	               gallery, status, CASE WHEN approx_location = 1 THEN 'approx' ELSE 'exact' END, sector_type
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
