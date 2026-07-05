package auth

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Section 27 — progressive per-phone OTP rate-limiting. When one phone number
// issues too many OTP requests inside a sliding window, it is locked for an
// escalating duration. This is separate from the per-IP window and the
// per-phone resend cooldown; it targets sustained abuse from one account.
const (
	// A phone may make up to otpPhoneMaxInWindow genuine OTP requests within
	// otpPhoneWindowSeconds before a lock triggers. (The resend cooldown means
	// each counted request is already spaced out.)
	otpPhoneWindowSeconds = int64(15 * 60) // 15-minute sliding window
	otpPhoneMaxInWindow   = 5
)

// otpLockDurations defines the escalating lock lengths: 1st lock 2h, 2nd 6h,
// 3rd and any subsequent lock 24h.
var otpLockDurations = []time.Duration{
	2 * time.Hour,
	6 * time.Hour,
	24 * time.Hour,
}

// PhoneLockStatus reports whether a phone is currently locked and, if so, how
// many seconds remain. A missing row or any error is treated as "not locked"
// (fail-open — a rate-limit bug must never wedge a legitimate user out).
func (s *OTPStore) PhoneLockStatus(ctx context.Context, phone string) (locked bool, retryAfter int) {
	var lockUntil int64
	err := s.Pool.QueryRow(ctx,
		`SELECT lock_until FROM otp_phone_locks WHERE phone = $1`, phone,
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

// RegisterPhoneRequest records one genuine OTP request for a phone and, if that
// pushes it past the window threshold, applies the next escalating lock.
// Returns (true, retryAfter) when the phone is now locked. Fail-open on error.
func (s *OTPStore) RegisterPhoneRequest(ctx context.Context, phone string) (locked bool, retryAfter int) {
	now := time.Now().Unix()

	var windowStart int64
	var count, lockLevel int
	var lockUntil int64
	err := s.Pool.QueryRow(ctx,
		`SELECT window_start, request_count, lock_level, lock_until
		   FROM otp_phone_locks WHERE phone = $1`, phone,
	).Scan(&windowStart, &count, &lockLevel, &lockUntil)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return false, 0
	}

	// Already locked (defensive — the handler checks first, but this keeps the
	// counter honest if two requests race).
	if lockUntil > now {
		return true, int(lockUntil - now)
	}

	// Reset the window on a new row or an expired window; otherwise increment.
	if errors.Is(err, pgx.ErrNoRows) || (now-windowStart) >= otpPhoneWindowSeconds {
		windowStart = now
		count = 1
	} else {
		count++
	}

	// Under the threshold → just persist the running count.
	if count <= otpPhoneMaxInWindow {
		_, _ = s.Pool.Exec(ctx,
			`INSERT INTO otp_phone_locks (phone, window_start, request_count, lock_level, lock_until)
			 VALUES ($1, $2, $3, $4, $5)
			 ON CONFLICT (phone) DO UPDATE
			   SET window_start = EXCLUDED.window_start,
			       request_count = EXCLUDED.request_count`,
			phone, windowStart, count, lockLevel, lockUntil)
		return false, 0
	}

	// Threshold exceeded → escalate the lock and reset the window counter.
	newLevel := lockLevel + 1
	dur := otpLockDurations[len(otpLockDurations)-1]
	if newLevel-1 < len(otpLockDurations) {
		dur = otpLockDurations[newLevel-1]
	}
	newLockUntil := now + int64(dur.Seconds())
	_, _ = s.Pool.Exec(ctx,
		`INSERT INTO otp_phone_locks (phone, window_start, request_count, lock_level, lock_until)
		 VALUES ($1, $2, 0, $3, $4)
		 ON CONFLICT (phone) DO UPDATE
		   SET window_start = EXCLUDED.window_start,
		       request_count = 0,
		       lock_level = EXCLUDED.lock_level,
		       lock_until = EXCLUDED.lock_until`,
		phone, now, newLevel, newLockUntil)
	return true, int(newLockUntil - now)
}
