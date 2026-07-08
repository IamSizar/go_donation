package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	DatabaseURL string
	HTTPPort    string
	AppEnv      string

	// Task #20 — sponsorship reminder scheduler. Off by default so nothing
	// fires until RUN_SCHEDULER=1 is set (mirrors RUN_MIGRATIONS).
	RunScheduler       bool
	SchedulerInterval  time.Duration // how often the scheduler wakes to scan
	ReminderDaysBefore int           // remind when due within this many days

	// Task #36 — support WhatsApp handoff. When set (digits, e.g. 9647500000000),
	// the in-app support chat offers "Continue on WhatsApp" after 3 messages.
	// Empty disables the offer.
	SupportWhatsApp string
}

func Load() (*Config, error) {
	// Railway (and most PaaS) inject the listen port as $PORT. Prefer it; fall
	// back to HTTP_PORT, then 8080 for local dev.
	port := os.Getenv("PORT")
	if port == "" {
		port = getEnvDefault("HTTP_PORT", "8080")
	}
	c := &Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		HTTPPort:    port,
		AppEnv:      getEnvDefault("APP_ENV", "development"),
	}
	if c.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required (copy backend/.env.example to backend/.env)")
	}

	// Task #20 — reminder scheduler config. All optional; safe defaults.
	c.RunScheduler = os.Getenv("RUN_SCHEDULER") == "1"
	c.SchedulerInterval = parseDurationDefault("SCHEDULER_INTERVAL", 6*time.Hour, time.Minute)
	c.ReminderDaysBefore = parseIntDefault("REMINDER_DAYS_BEFORE", 3, 0, 60)

	// Task #36 — support WhatsApp number (digits only, no + or spaces).
	c.SupportWhatsApp = strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, os.Getenv("SUPPORT_WHATSAPP"))

	return c, nil
}

// parseDurationDefault reads a Go duration string (e.g. "6h", "30m") from the
// environment, clamping to a sane minimum so a typo can't spin the scheduler
// into a hot loop. Falls back to def when unset or unparseable.
func parseDurationDefault(key string, def, min time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil || d < min {
		return def
	}
	return d
}

// parseIntDefault reads an int from the environment, clamped to [min,max].
// Falls back to def when unset or unparseable.
func parseIntDefault(key string, def, min, max int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	if n < min {
		n = min
	}
	if n > max {
		n = max
	}
	return n
}

func getEnvDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// GetEnvDefault is the exported form of getEnvDefault for other packages.
func GetEnvDefault(key, fallback string) string { return getEnvDefault(key, fallback) }
