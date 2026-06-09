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
	ID            int64   `json:"id"`
	Name          string  `json:"name"`
	NameAr        *string `json:"name_ar"`
	NameSorani    *string `json:"name_sorani"`
	NameBadini    *string `json:"name_badini"`
	PartnerType   *string `json:"partner_type"`
	ContactPhone  *string `json:"contact_phone"`
	Website       *string `json:"website"`
	Description   *string `json:"description"`
	DescriptionAr *string `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	LogoPath      *string `json:"logo_path"`
	Status        string  `json:"status"`
}

// ListPartners returns partners. status="" → no filter. Public default is
// "active"; the admin SPA can pass "" to see every status. q is an optional
// free-text search across name/name_ar/partner_type.
func (s *Store) ListPartners(ctx context.Context, status, q string, limit int) ([]Partner, error) {
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
	sql := `SELECT id, name, name_ar, name_sorani, name_badini,
	               partner_type, contact_phone, website,
	               description, description_ar, description_sorani, description_badini,
	               logo_path, status
	          FROM partners` + whereSQL + ` ORDER BY name ASC LIMIT ` + itoa(limit)

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
		); err != nil {
			return nil, err
		}
		items = append(items, p)
	}
	return items, rows.Err()
}

// ----------------- media posts -----------------

type MediaPost struct {
	ID         int64      `json:"id"`
	Title      string     `json:"title"`
	TitleAr    *string    `json:"title_ar"`
	TitleSorani *string   `json:"title_sorani"`
	TitleBadini *string   `json:"title_badini"`
	Body       *string    `json:"body"`
	BodyAr     *string    `json:"body_ar"`
	BodySorani *string    `json:"body_sorani"`
	BodyBadini *string    `json:"body_badini"`
	PostType   string     `json:"post_type"`
	MediaURL   *string    `json:"media_url"`
	LinkURL    *string    `json:"link_url"`
	EventDate  *time.Time `json:"event_date"`
	Status     string     `json:"status"`
	CreatedAt  time.Time  `json:"created_at"`
}

// ListMediaPosts returns media posts. status="" → no filter. Public default is
// "published". q is an optional free-text search across title/title_ar/body.
func (s *Store) ListMediaPosts(ctx context.Context, status, postType, q string, limit int) ([]MediaPost, error) {
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
	sql := `SELECT id, title, title_ar, title_sorani, title_badini,
	               body, body_ar, body_sorani, body_badini,
	               post_type, media_url, link_url, event_date, status, created_at
	          FROM media_posts` + whereSQL + `
	         ORDER BY COALESCE(event_date, created_at::date) DESC, id DESC
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
		); err != nil {
			return nil, err
		}
		items = append(items, m)
	}
	return items, rows.Err()
}

// ----------------- city directory / community -----------------

type Community struct {
	ID            int64    `json:"id"`
	Name          string   `json:"name"`
	NameAr        *string  `json:"name_ar"`
	NameSorani    *string  `json:"name_sorani"`
	NameBadini    *string  `json:"name_badini"`
	Category      string   `json:"category"`
	City          *string  `json:"city"`
	Address       *string  `json:"address"`
	Phone         *string  `json:"phone"`
	Email         *string  `json:"email"`
	Website       *string  `json:"website"`
	Description   *string  `json:"description"`
	DescriptionAr *string  `json:"description_ar"`
	DescriptionSorani *string `json:"description_sorani"`
	DescriptionBadini *string `json:"description_badini"`
	Latitude      *string  `json:"latitude"`
	Longitude     *string  `json:"longitude"`
}

// ListCommunity returns approved community-directory entries. q searches
// across name, name_ar, address, phone, and category.
func (s *Store) ListCommunity(ctx context.Context, category, city, q string, limit int) ([]Community, error) {
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
	if q = strings.TrimSpace(q); q != "" {
		args = append(args, "%"+q+"%")
		idx := itoa(len(args))
		where = append(where, "(name ILIKE $"+idx+" OR name_ar ILIKE $"+idx+" OR address ILIKE $"+idx+" OR phone ILIKE $"+idx+" OR category ILIKE $"+idx+")")
	}
	sql := `SELECT id, name, name_ar, name_sorani, name_badini,
	               category, city, address, phone, email, website,
	               description, description_ar, description_sorani, description_badini,
	               latitude::text, longitude::text
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
		); err != nil {
			return nil, err
		}
		items = append(items, c)
	}
	return items, rows.Err()
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
