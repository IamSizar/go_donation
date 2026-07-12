package handlers

import (
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// permChangeLimiter is a lightweight, in-memory, per-actor rate limiter for
// permission changes — the §24 "suspicious activity" guard, layered on top of
// the single-use SMS OTP that every change ALREADY requires. It is DISABLED
// unless PERM_CHANGE_MAX_PER_MIN is set to a positive integer, so default
// behaviour is unchanged and a misconfiguration can never lock the Super-Admin
// out of tuning permissions. Deliberately not a hard account lock (that would
// risk locking the only Super-Admin out of their own dashboard) — it throttles
// with a 429 and clears itself after the one-minute window.
type permChangeLimiter struct {
	mu     sync.Mutex
	hits   map[int64][]time.Time
	window time.Duration
	max    int
}

var permLimiter = newPermChangeLimiter()

func newPermChangeLimiter() *permChangeLimiter {
	max := 0
	if v := strings.TrimSpace(os.Getenv("PERM_CHANGE_MAX_PER_MIN")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			max = n
		}
	}
	return &permChangeLimiter{hits: map[int64][]time.Time{}, window: time.Minute, max: max}
}

// allow records an attempt for actorID at time now and reports whether it is
// within the per-minute limit. When disabled (max<=0) it always allows.
func (l *permChangeLimiter) allow(actorID int64, now time.Time) bool {
	if l.max <= 0 {
		return true
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	cutoff := now.Add(-l.window)
	// In-place filter to drop timestamps outside the window.
	kept := l.hits[actorID][:0]
	for _, ts := range l.hits[actorID] {
		if ts.After(cutoff) {
			kept = append(kept, ts)
		}
	}
	if len(kept) >= l.max {
		l.hits[actorID] = kept
		return false
	}
	l.hits[actorID] = append(kept, now)
	return true
}
