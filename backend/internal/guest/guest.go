// Package guest implements Section 27 "Guest Mode" — a signed-out browsing
// role whose visible app screens are configured by the Super Admin.
package guest

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

var errUnknownScreen = errors.New("unknown guest screen")

// Screen is one browseable app screen the Super Admin can expose to guests.
type Screen struct {
	Key            string `json:"key"`
	DefaultEnabled bool   `json:"-"`
}

// Screens is the canonical list guests can be granted. Keep the keys in sync
// with the mobile app's screen router. Defaults: read-only public content is
// on; account-leaning screens (marketplace/marriage/volunteer) start off and
// the Super Admin opts them in.
var Screens = []Screen{
	{Key: "campaigns", DefaultEnabled: true},
	{Key: "news", DefaultEnabled: true},
	{Key: "city_directory", DefaultEnabled: true},
	{Key: "partners", DefaultEnabled: true},
	{Key: "marketplace", DefaultEnabled: false},
	{Key: "marriage", DefaultEnabled: false},
	{Key: "volunteer", DefaultEnabled: false},
}

func isKnownScreen(key string) bool {
	for _, s := range Screens {
		if s.Key == key {
			return true
		}
	}
	return false
}

// Store backs the guest_settings override table.
type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Config returns the effective enabled-map for every screen: the code default
// unless a stored override says otherwise.
func (s *Store) Config(ctx context.Context) (map[string]bool, error) {
	out := map[string]bool{}
	for _, sc := range Screens {
		out[sc.Key] = sc.DefaultEnabled
	}
	rows, err := s.Pool.Query(ctx, `SELECT screen, enabled FROM guest_settings`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var key string
		var enabled bool
		if err := rows.Scan(&key, &enabled); err != nil {
			return nil, err
		}
		if _, ok := out[key]; ok { // ignore stale rows for removed screens
			out[key] = enabled
		}
	}
	return out, rows.Err()
}

// SetScreen upserts an enabled override for one screen.
func (s *Store) SetScreen(ctx context.Context, screen string, enabled bool) error {
	if !isKnownScreen(screen) {
		return errUnknownScreen
	}
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO guest_settings (screen, enabled, updated_at)
		 VALUES ($1, $2, NOW())
		 ON CONFLICT (screen) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = NOW()`,
		screen, enabled)
	return err
}

// ScreenEnabled reports whether a single screen is guest-visible (used for
// server-side enforcement of guest access).
func (s *Store) ScreenEnabled(ctx context.Context, screen string) (bool, error) {
	cfg, err := s.Config(ctx)
	if err != nil {
		return false, err
	}
	return cfg[screen], nil
}
