// Package appsettings is a tiny key/value store over the app_settings table.
// Thin pgxpool wrapper in the same style as content.Store / guest.Store.
//
// First consumer (#36): the admin-editable support WhatsApp number.
package appsettings

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// KeySupportWhatsApp is the settings key for the AI-chat WhatsApp handoff number.
const KeySupportWhatsApp = "support_whatsapp"

type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Get returns the value for key, or "" when the key has no row (never an error
// for a missing key — callers treat empty as "unset").
func (s *Store) Get(ctx context.Context, key string) (string, error) {
	var v string
	err := s.Pool.QueryRow(ctx,
		`SELECT value FROM app_settings WHERE key = $1`, key).Scan(&v)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return v, nil
}

// Set upserts a key/value pair.
func (s *Store) Set(ctx context.Context, key, value string) error {
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO app_settings (key, value, updated_at)
		 VALUES ($1, $2, CURRENT_TIMESTAMP)
		 ON CONFLICT (key) DO UPDATE
		   SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP`,
		key, value)
	return err
}
