// Package events stores the activity/analytics event log (the Postgres home
// for what used to be the Firestore `events` collection). The mobile app
// appends a row per meaningful action; the admin dashboard reads the most
// recent rows for its live feed.
package events

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is the app_events data access layer.
type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Event mirrors a row of app_events. JSON tags match exactly what the mobile
// app sends and what the admin feed consumes, so neither side needs a mapping
// shim.
type Event struct {
	ID            int64                  `json:"id"`
	EventType     string                 `json:"event_type"`
	EventLabel    string                 `json:"event_label,omitempty"`
	Module        string                 `json:"module,omitempty"`
	Action        string                 `json:"action,omitempty"`
	Status        string                 `json:"status,omitempty"`
	Source        string                 `json:"source,omitempty"`
	UserID        *int64                 `json:"user_id,omitempty"`
	RoleID        *int64                 `json:"role_id,omitempty"`
	Name          string                 `json:"name,omitempty"`
	Number        string                 `json:"number,omitempty"`
	NumberDigits  string                 `json:"number_digits,omitempty"`
	EntityID      *int64                 `json:"entity_id,omitempty"`
	TargetID      *int64                 `json:"target_id,omitempty"`
	Amount        *float64               `json:"amount,omitempty"`
	Currency      string                 `json:"currency,omitempty"`
	PaymentMethod string                 `json:"payment_method,omitempty"`
	ContentLocale string                 `json:"content_locale,omitempty"`
	Note          string                 `json:"note,omitempty"`
	Metadata      map[string]interface{} `json:"metadata,omitempty"`
	IsRead        bool                   `json:"is_read"`
	AdminState    string                 `json:"admin_state,omitempty"`
	CreatedAtMs   int64                  `json:"created_at_ms"`
}

// Insert appends an event and returns its new id. metadata is stored as JSONB.
func (s *Store) Insert(ctx context.Context, e Event) (int64, error) {
	meta := e.Metadata
	if meta == nil {
		meta = map[string]interface{}{}
	}
	metaJSON, err := json.Marshal(meta)
	if err != nil {
		metaJSON = []byte("{}")
	}
	status := e.Status
	if status == "" {
		status = "success"
	}
	source := e.Source
	if source == "" {
		source = "app"
	}

	var id int64
	err = s.Pool.QueryRow(ctx, `
		INSERT INTO app_events (
			event_type, event_label, module, action, status, source,
			user_id, role_id, name, number, number_digits,
			entity_id, target_id, amount, currency, payment_method,
			content_locale, note, metadata, created_at_ms
		) VALUES (
			$1, $2, $3, $4, $5, $6,
			$7, $8, $9, $10, $11,
			$12, $13, $14, $15, $16,
			$17, $18, $19, $20
		) RETURNING id`,
		e.EventType, e.EventLabel, e.Module, e.Action, status, source,
		e.UserID, e.RoleID, e.Name, e.Number, e.NumberDigits,
		e.EntityID, e.TargetID, e.Amount, e.Currency, e.PaymentMethod,
		e.ContentLocale, e.Note, metaJSON, e.CreatedAtMs,
	).Scan(&id)
	return id, err
}

// Delete permanently removes one event row. Returns whether a row was deleted.
// Wired only to a Super-Admin-gated route (the Notification Center's purge),
// matching the "deletable only by the Primary Administrator" rule.
func (s *Store) Delete(ctx context.Context, id int64) (bool, error) {
	ct, err := s.Pool.Exec(ctx, "DELETE FROM app_events WHERE id = $1", id)
	if err != nil {
		return false, err
	}
	return ct.RowsAffected() > 0, nil
}

// List returns the most recent events, newest first.
func (s *Store) List(ctx context.Context, limit int) ([]Event, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT
			id, event_type,
			COALESCE(event_label, ''), COALESCE(module, ''), COALESCE(action, ''),
			COALESCE(status, ''), COALESCE(source, ''),
			user_id, role_id,
			COALESCE(name, ''), COALESCE(number, ''), COALESCE(number_digits, ''),
			entity_id, target_id, amount,
			COALESCE(currency, ''), COALESCE(payment_method, ''),
			COALESCE(content_locale, ''), COALESCE(note, ''),
			metadata, is_read, COALESCE(admin_state, ''), created_at_ms
		FROM app_events
		ORDER BY created_at_ms DESC
		LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Event, 0, limit)
	for rows.Next() {
		var e Event
		var metaJSON []byte
		if err := rows.Scan(
			&e.ID, &e.EventType,
			&e.EventLabel, &e.Module, &e.Action,
			&e.Status, &e.Source,
			&e.UserID, &e.RoleID,
			&e.Name, &e.Number, &e.NumberDigits,
			&e.EntityID, &e.TargetID, &e.Amount,
			&e.Currency, &e.PaymentMethod,
			&e.ContentLocale, &e.Note,
			&metaJSON, &e.IsRead, &e.AdminState, &e.CreatedAtMs,
		); err != nil {
			return nil, err
		}
		if len(metaJSON) > 0 {
			_ = json.Unmarshal(metaJSON, &e.Metadata)
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
