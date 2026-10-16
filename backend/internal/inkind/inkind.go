// Package inkind handles in_kind_donations.
package inkind

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type InKindDonation struct {
	ID            int64     `json:"id"`
	DonorUserID   *int      `json:"donor_user_id"`
	Category      string    `json:"category"`
	ItemName      string    `json:"item_name"`
	Quantity      *string   `json:"quantity"`
	ConditionNote *string   `json:"condition_note"`
	PickupAddress *string   `json:"pickup_address"`
	Status        string    `json:"status"`
	Notes         *string   `json:"notes"`
	CreatedAt     time.Time `json:"created_at"`
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// List returns in-kind donations (optionally filtered to a single donor).
func (s *Store) List(ctx context.Context, userID int64, limit int) ([]InKindDonation, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	args := []any{}
	q := `SELECT id, donor_user_id, category, item_name, quantity,
	             condition_note, pickup_address, status, notes, created_at
	        FROM in_kind_donations`
	if userID > 0 {
		args = append(args, userID)
		q += ` WHERE donor_user_id = $1`
	}
	q += ` ORDER BY id DESC LIMIT ` + itoa(limit)

	rows, err := s.Pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []InKindDonation{}
	for rows.Next() {
		var x InKindDonation
		if err := rows.Scan(&x.ID, &x.DonorUserID, &x.Category, &x.ItemName, &x.Quantity,
			&x.ConditionNote, &x.PickupAddress, &x.Status, &x.Notes, &x.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

// Insert writes a new in-kind donation row.
func (s *Store) Insert(ctx context.Context, donorUserID int64, category, itemName string,
	quantity, conditionNote, pickupAddress, notes *string) (int64, error) {
	if donorUserID <= 0 {
		return 0, errors.New("invalid donorUserID")
	}
	category = strings.TrimSpace(category)
	itemName = strings.TrimSpace(itemName)
	if category == "" || itemName == "" {
		return 0, errors.New("missing category or item_name")
	}
	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO in_kind_donations
		   (donor_user_id, category, item_name, quantity, condition_note, pickup_address, notes)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id`,
		donorUserID, category, itemName, quantity, conditionNote, pickupAddress, notes,
	).Scan(&id)
	return id, err
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}
