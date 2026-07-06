// Package partnerratings backs the 1–5 star partner rating (#27). Each user has
// at most one rating per partner (upsert). After every submit the partner's
// denormalized avg_rating / rating_count are recomputed so the public list can
// show them without a join.
package partnerratings

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Result is what the rate endpoint returns to the app.
type Result struct {
	AvgRating   float64 `json:"avg_rating"`
	RatingCount int     `json:"rating_count"`
	MyRating    int     `json:"my_rating"`
}

// Submit upserts the user's rating for a partner (1–5), then recomputes the
// partner's aggregate. Returns ErrNoRows if the partner doesn't exist.
func (s *Store) Submit(ctx context.Context, partnerID, userID int64, stars int) (*Result, error) {
	if stars < 1 || stars > 5 {
		return nil, errors.New("stars must be between 1 and 5")
	}

	// Guard: the partner must exist (no FK enforced, so check explicitly).
	var exists bool
	if err := s.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM partners WHERE id = $1)`, partnerID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, pgx.ErrNoRows
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx,
		`INSERT INTO partner_ratings (partner_id, user_id, stars)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (partner_id, user_id)
		 DO UPDATE SET stars = EXCLUDED.stars, updated_at = CURRENT_TIMESTAMP`,
		partnerID, userID, stars); err != nil {
		return nil, err
	}

	// Recompute the denormalized aggregate on the partner row.
	var res Result
	if err := tx.QueryRow(ctx,
		`UPDATE partners p
		    SET avg_rating   = agg.avg,
		        rating_count = agg.cnt,
		        updated_at   = CURRENT_TIMESTAMP
		   FROM (SELECT ROUND(AVG(stars)::numeric, 2) AS avg, COUNT(*) AS cnt
		           FROM partner_ratings WHERE partner_id = $1) agg
		  WHERE p.id = $1
		  RETURNING COALESCE(p.avg_rating, 0)::float8, p.rating_count`,
		partnerID).Scan(&res.AvgRating, &res.RatingCount); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	res.MyRating = stars
	return &res, nil
}
