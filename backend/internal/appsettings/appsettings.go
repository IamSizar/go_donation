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

// Donations Page spec — donate-screen switches, both editable from the
// Dashboard.
//
// KeyDonationProjectsVisible: "the project list can also be hidden, leaving
// only the General Donation option".
const KeyDonationProjectsVisible = "donation_projects_visible"

// KeyDonationComprehensiveEnabled toggles the "Fifth: Comprehensive Grantor
// Option" (Grant Now / Comprehensive Grant) general-fund choice.
const KeyDonationComprehensiveEnabled = "donation_comprehensive_enabled"

// KeySupportWhatsApp is the settings key for the AI-chat WhatsApp handoff number.
const KeySupportWhatsApp = "support_whatsapp"

// KeySupportUserID is the settings key for the staff account that receives
// "Message the staff team" chats (marriage↔tech-support and similar pairs).
// Admin-configurable so it doesn't require redeploying with a new env var.
const KeySupportUserID = "support_user_id"

// KeyAssistantEnabled toggles the AI (tool-calling) path of the Support
// Assistant on/off. "false" disables it; anything else (including unset)
// leaves it on. When off, /assistant/chat silently uses the deterministic
// keyword-fallback engine instead — the feature stays usable, just without
// free-form understanding, letting staff kill the LLM cost path anytime.
const KeyAssistantEnabled = "assistant_enabled"

// KeyAssistantExtraInstructions is free text an admin can add to the
// assistant's system prompt (tone, scope nudges) without a redeploy.
const KeyAssistantExtraInstructions = "assistant_extra_instructions"

// KeyPartnerRatingsVisible hides the 1-5 partner rating from the app.
// "false" hides it; anything else (including unset) leaves it visible, so the
// existing behaviour is what you get until an admin turns it off.
//
// Enforced server-side rather than by asking the app not to draw it: when it
// is off the public partners list carries no rating at all, so nothing that
// reads the API can display one. Staff keep seeing and editing ratings in the
// Admin Panel — hiding is about what the public sees, not about losing the
// scores.
const KeyPartnerRatingsVisible = "partner_ratings_visible"

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
