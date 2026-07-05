package auth

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Requirement 6c — login brute-force throttle. This mirrors the OTP per-phone
// lockout (otp_lock.go) but keys on a login identity and counts FAILED password
// attempts (not requests). When one identity fails too many times inside a
// sliding window it is locked for an escalating duration; a successful login
// clears the counter.
//
// The identifier is namespaced by the caller so phone-login and admin-username
// login share the login_attempts table without colliding:
//
//	"p:<canonical_phone>"   — mobile / phone password login
//	"u:<username>"          — admin dashboard login
const (
	// Up to loginMaxFails failed attempts are tolerated within loginWindowSeconds
	// before a lock triggers.
	loginWindowSeconds = int64(15 * 60) // 15-minute sliding window
	loginMaxFails      = 5
)

// loginLockDurations defines the escalating lock lengths: 1st lock 15m, 2nd 1h,
// 3rd and any subsequent lock 24h.
var loginLockDurations = []time.Duration{
	15 * time.Minute,
	1 * time.Hour,
	24 * time.Hour,
}

// LoginLockStore backs the login_attempts table (migration 023).
type LoginLockStore struct {
	Pool *pgxpool.Pool
}

func NewLoginLockStore(pool *pgxpool.Pool) *LoginLockStore {
	return &LoginLockStore{Pool: pool}
}

// Status reports whether an identity is currently locked and, if so, how many
// seconds remain. A missing row or any error is treated as "not locked"
// (fail-open — a throttle bug must never wedge every user out of login).
func (s *LoginLockStore) Status(ctx context.Context, identifier string) (locked bool, retryAfter int) {
	var lockUntil int64
	err := s.Pool.QueryRow(ctx,
		`SELECT lock_until FROM login_attempts WHERE identifier = $1`, identifier,
	).Scan(&lockUntil)
	if err != nil {
		return false, 0
	}
	now := time.Now().Unix()
	if lockUntil > now {
		return true, int(lockUntil - now)
	}
	return false, 0
}

// RegisterFailure records one failed login for an identity and, if that pushes
// it past the window threshold, applies the next escalating lock. Returns
// (true, retryAfter) when the identity is now locked. Fail-open on error.
func (s *LoginLockStore) RegisterFailure(ctx context.Context, identifier string) (locked bool, retryAfter int) {
	now := time.Now().Unix()

	var windowStart int64
	var count, lockLevel int
	var lockUntil int64
	err := s.Pool.QueryRow(ctx,
		`SELECT window_start, fail_count, lock_level, lock_until
		   FROM login_attempts WHERE identifier = $1`, identifier,
	).Scan(&windowStart, &count, &lockLevel, &lockUntil)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return false, 0
	}

	// Already locked (defensive — the handler checks first, but this keeps the
	// counter honest if two failures race).
	if lockUntil > now {
		return true, int(lockUntil - now)
	}

	// Reset the window on a new row or an expired window; otherwise increment.
	if errors.Is(err, pgx.ErrNoRows) || (now-windowStart) >= loginWindowSeconds {
		windowStart = now
		count = 1
	} else {
		count++
	}

	// Under the threshold → just persist the running count.
	if count <= loginMaxFails {
		_, _ = s.Pool.Exec(ctx,
			`INSERT INTO login_attempts (identifier, window_start, fail_count, lock_level, lock_until)
			 VALUES ($1, $2, $3, $4, $5)
			 ON CONFLICT (identifier) DO UPDATE
			   SET window_start = EXCLUDED.window_start,
			       fail_count = EXCLUDED.fail_count`,
			identifier, windowStart, count, lockLevel, lockUntil)
		return false, 0
	}

	// Threshold exceeded → escalate the lock and reset the window counter.
	newLevel := lockLevel + 1
	dur := loginLockDurations[len(loginLockDurations)-1]
	if newLevel-1 < len(loginLockDurations) {
		dur = loginLockDurations[newLevel-1]
	}
	newLockUntil := now + int64(dur.Seconds())
	_, _ = s.Pool.Exec(ctx,
		`INSERT INTO login_attempts (identifier, window_start, fail_count, lock_level, lock_until)
		 VALUES ($1, $2, 0, $3, $4)
		 ON CONFLICT (identifier) DO UPDATE
		   SET window_start = EXCLUDED.window_start,
		       fail_count = 0,
		       lock_level = EXCLUDED.lock_level,
		       lock_until = EXCLUDED.lock_until`,
		identifier, now, newLevel, newLockUntil)
	return true, int(newLockUntil - now)
}

// Reset clears the failed-attempt counter for an identity after a successful
// login. A clean login wipes the row entirely (counter and lock_level), so any
// future lock starts again from the first (shortest) tier. A brute-forcer never
// reaches this path, so their escalation is unaffected.
func (s *LoginLockStore) Reset(ctx context.Context, identifier string) {
	_, _ = s.Pool.Exec(ctx, `DELETE FROM login_attempts WHERE identifier = $1`, identifier)
}
