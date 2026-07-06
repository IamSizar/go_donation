// Package sectioncodes manages per-section donation transaction-code namespaces
// (#14): each donation_kind has its own prefix and an independent running
// sequence, producing references like CAM-000042. Prefixes are admin-editable;
// numbers are issued atomically.
package sectioncodes

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a kind has no configured namespace row.
var ErrNotFound = errors.New("donation section code not found")

// SectionCode is one section's namespace config (its prefix and the next
// sequence number that will be issued).
type SectionCode struct {
	Kind          string    `json:"kind"`
	Prefix        string    `json:"prefix"`
	NextSeq       int64     `json:"next_seq"`
	NotifyPhone   string    `json:"notify_phone"`   // #15 — SMS contact ('' = none)
	NotifyEnabled bool      `json:"notify_enabled"` // #15 — arrival-SMS on/off
	UpdatedAt     time.Time `json:"updated_at"`
}

// Querier is the small subset of pgx used by NextReference — satisfied by both
// *pgxpool.Pool and pgx.Tx. Passing a transaction makes the number consumption
// roll back with the donation (gapless); passing the pool issues a standalone
// number.
type Querier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// List returns every section's code config, ordered by kind.
func (s *Store) List(ctx context.Context) ([]SectionCode, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT kind, prefix, next_seq, COALESCE(notify_phone, ''), (notify_enabled = 1), updated_at
		   FROM donation_section_codes ORDER BY kind`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]SectionCode, 0, 5)
	for rows.Next() {
		var sc SectionCode
		if err := rows.Scan(&sc.Kind, &sc.Prefix, &sc.NextSeq, &sc.NotifyPhone, &sc.NotifyEnabled, &sc.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, sc)
	}
	return out, rows.Err()
}

// UpdateSection sets a section's editable config — code prefix (#14), notify
// phone and notify toggle (#15). An empty phone clears it (stored NULL).
// Returns ErrNotFound if the kind has no row.
func (s *Store) UpdateSection(ctx context.Context, kind, prefix, phone string, enabled bool, updatedBy int64) error {
	enabledInt := 0
	if enabled {
		enabledInt = 1
	}
	ct, err := s.Pool.Exec(ctx,
		`UPDATE donation_section_codes
		    SET prefix = $2,
		        notify_phone = NULLIF($3, ''),
		        notify_enabled = $4,
		        updated_at = CURRENT_TIMESTAMP,
		        updated_by = $5
		  WHERE kind = $1`,
		kind, prefix, phone, enabledInt, updatedBy)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// GetNotify returns a section's notify phone and toggle (#15). ok=false when the
// kind has no row.
func (s *Store) GetNotify(ctx context.Context, kind string) (phone string, enabled, ok bool, err error) {
	scanErr := s.Pool.QueryRow(ctx,
		`SELECT COALESCE(notify_phone, ''), (notify_enabled = 1)
		   FROM donation_section_codes WHERE kind = $1`,
		kind,
	).Scan(&phone, &enabled)
	if errors.Is(scanErr, pgx.ErrNoRows) {
		return "", false, false, nil
	}
	if scanErr != nil {
		return "", false, false, scanErr
	}
	return phone, enabled, true, nil
}

// NextReference atomically consumes the next number in kind's namespace and
// returns the formatted reference (e.g. "CAM-000042"). The single
// UPDATE … RETURNING is race-safe (row lock), so concurrent donors never
// collide. Returns ok=false when the kind has no config row, letting the caller
// fall back to its legacy format.
func (s *Store) NextReference(ctx context.Context, q Querier, kind string) (code string, ok bool, err error) {
	var prefix string
	var seq int64
	scanErr := q.QueryRow(ctx,
		`UPDATE donation_section_codes
		    SET next_seq = next_seq + 1, updated_at = CURRENT_TIMESTAMP
		  WHERE kind = $1
		  RETURNING prefix, next_seq - 1`,
		kind,
	).Scan(&prefix, &seq)
	if errors.Is(scanErr, pgx.ErrNoRows) {
		return "", false, nil
	}
	if scanErr != nil {
		return "", false, scanErr
	}
	return fmt.Sprintf("%s-%06d", prefix, seq), true, nil
}
