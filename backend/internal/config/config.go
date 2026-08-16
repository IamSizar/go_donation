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

	// H20 — outbound email. Unset in every environment today; see SMTPConfig
	// for what an unset value means at each call site.
	SMTP SMTPConfig
}

// SMTPConfig is everything the standard-library mail sender needs
// (internal/auth/mailer.go). Deliberately five plain strings/int rather than a
// provider SDK: the only thing this system sends is a short confirmation code,
// and a dependency is a liability.
//
// CONFIGURED means Host, Port and From are all present. Username/Password are
// optional — some relays authenticate by IP — but if EITHER is supplied the
// sender demands TLS before offering it (see Mailer.Send), because a password
// handed to a plaintext relay is a password published.
//
// Every field is empty in every environment the team can reach today. That is
// not a bug to route around: each caller decides, deliberately and visibly,
// what "no email channel" means for it, and none of them may report success
// for a message that never left. See Mailer.Configured.
type SMTPConfig struct {
	Host     string // e.g. smtp.gmail.com
	Port     int    // 587 (STARTTLS) or 465 (implicit TLS); 0 when unset
	Username string
	Password string // NEVER logged, never returned in an API response
	From     string // envelope + header From, e.g. "no-reply@example.org"
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

	// H20 — outbound email. Port defaults to 587 (submission + STARTTLS), the
	// port a relay is most likely to be reachable on; 465 is the implicit-TLS
	// alternative and the sender picks the right handshake from the number.
	// Clamped to a real port range so a typo degrades to "unconfigured" — which
	// every caller handles — instead of a dial to port 0 that hangs a request.
	c.SMTP = SMTPConfig{
		Host:     strings.TrimSpace(os.Getenv("SMTP_HOST")),
		Port:     parseIntDefault("SMTP_PORT", 587, 1, 65535),
		Username: strings.TrimSpace(os.Getenv("SMTP_USERNAME")),
		Password: os.Getenv("SMTP_PASSWORD"), // not trimmed: spaces can be significant
		From:     strings.TrimSpace(os.Getenv("SMTP_FROM")),
	}

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
