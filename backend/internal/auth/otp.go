package auth

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"net"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

const (
	OTPTTL                  = 5 * time.Minute  // matches OTP_TTL_SECONDS
	OTPMaxAttempts          = 5                // matches OTP_MAX_ATTEMPTS
	OTPResendCooldown       = 60 * time.Second // matches OTP_RESEND_COOLDOWN_SECONDS
	OTPIPRateWindowSeconds  = 3600
	OTPIPRateDefaultPerHour = 10
)

var otpCodeFormatRE = regexp.MustCompile(`^\d{6}$`)

// OTPRecord mirrors the fields the verify endpoint needs.
type OTPRecord struct {
	Phone     string
	CodeHash  string
	Mode      string // "real" or "demo"
	Attempts  int
	SentAt    time.Time
	ExpiresAt time.Time
}

type OTPStore struct {
	Pool *pgxpool.Pool
}

func NewOTPStore(pool *pgxpool.Pool) *OTPStore {
	return &OTPStore{Pool: pool}
}

// GenerateCode returns a zero-padded 6-digit code, matching otp_generate_code().
func GenerateCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// ValidateCodeFormat returns true if the input is exactly 6 digits.
func ValidateCodeFormat(code string) bool {
	return otpCodeFormatRE.MatchString(strings.TrimSpace(code))
}

// StoreCode upserts an OTP record for the given phone. mode must be "real" or "demo".
func (s *OTPStore) StoreCode(ctx context.Context, phone, code, mode string) error {
	if mode != "demo" {
		mode = "real"
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash code: %w", err)
	}
	now := time.Now().UTC()
	_, err = s.Pool.Exec(ctx,
		`INSERT INTO otp_codes (phone, code_hash, mode, attempts, sent_at, expires_at)
		 VALUES ($1, $2, $3, 0, $4, $5)
		 ON CONFLICT (phone) DO UPDATE
		   SET code_hash  = EXCLUDED.code_hash,
		       mode       = EXCLUDED.mode,
		       attempts   = 0,
		       sent_at    = EXCLUDED.sent_at,
		       expires_at = EXCLUDED.expires_at`,
		phone, string(hash), mode, now, now.Add(OTPTTL),
	)
	return err
}

// GetRecord returns the OTP record for a phone, or nil if none exists.
func (s *OTPStore) GetRecord(ctx context.Context, phone string) (*OTPRecord, error) {
	rec := &OTPRecord{Phone: phone}
	err := s.Pool.QueryRow(ctx,
		`SELECT code_hash, mode, attempts, sent_at, expires_at
		   FROM otp_codes WHERE phone = $1`,
		phone,
	).Scan(&rec.CodeHash, &rec.Mode, &rec.Attempts, &rec.SentAt, &rec.ExpiresAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return rec, nil
}

// IncAttempts bumps the failed-attempt counter. Returns the new value.
func (s *OTPStore) IncAttempts(ctx context.Context, phone string) (int, error) {
	var n int
	err := s.Pool.QueryRow(ctx,
		`UPDATE otp_codes SET attempts = attempts + 1
		  WHERE phone = $1
		  RETURNING attempts`,
		phone,
	).Scan(&n)
	return n, err
}

// ClearRecord removes the OTP record after success or terminal failure.
func (s *OTPStore) ClearRecord(ctx context.Context, phone string) error {
	_, err := s.Pool.Exec(ctx, `DELETE FROM otp_codes WHERE phone = $1`, phone)
	return err
}

// VerifyCode constant-time-compares the provided code against the stored hash.
func VerifyCode(stored, provided string) bool {
	if stored == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(stored), []byte(provided)) == nil
}

// IPRateResult is the outcome of an IP-level rate check.
type IPRateResult struct {
	Allowed    bool
	RetryAfter int // seconds
	Remaining  int // -1 when unknown
}

// CheckIPRate counts and records OTP requests per IP. Fails open on DB errors
// so a flap can't DOS-lock the OTP flow (matches PHP fail-open behavior).
func (s *OTPStore) CheckIPRate(ctx context.Context, ip string) IPRateResult {
	if ip == "" {
		return IPRateResult{Allowed: true, Remaining: -1}
	}
	max := ipRateLimitMax()
	now := time.Now().Unix()

	var windowStart int64
	var count int
	err := s.Pool.QueryRow(ctx,
		`SELECT window_start, request_count FROM otp_ip_rate_limit WHERE ip_address = $1`,
		ip,
	).Scan(&windowStart, &count)

	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return IPRateResult{Allowed: true, Remaining: -1}
	}

	// Fresh window: new row or expired window.
	if errors.Is(err, pgx.ErrNoRows) || (now-windowStart) >= OTPIPRateWindowSeconds {
		_, upErr := s.Pool.Exec(ctx,
			`INSERT INTO otp_ip_rate_limit (ip_address, window_start, request_count)
			 VALUES ($1, $2, 1)
			 ON CONFLICT (ip_address) DO UPDATE
			   SET window_start = EXCLUDED.window_start,
			       request_count = 1`,
			ip, now,
		)
		if upErr != nil {
			return IPRateResult{Allowed: true, Remaining: -1}
		}
		return IPRateResult{Allowed: true, Remaining: max - 1}
	}

	if count >= max {
		retry := OTPIPRateWindowSeconds - (now - windowStart)
		if retry < 1 {
			retry = 1
		}
		return IPRateResult{Allowed: false, RetryAfter: int(retry), Remaining: 0}
	}

	_, _ = s.Pool.Exec(ctx,
		`UPDATE otp_ip_rate_limit SET request_count = request_count + 1 WHERE ip_address = $1`,
		ip)
	return IPRateResult{Allowed: true, Remaining: max - count - 1}
}

func ipRateLimitMax() int {
	if v := os.Getenv("OTP_IP_MAX_REQUESTS_PER_HOUR"); v != "" {
		var n int
		if _, err := fmt.Sscanf(strings.TrimSpace(v), "%d", &n); err == nil && n >= 1 && n <= 1000 {
			return n
		}
	}
	return OTPIPRateDefaultPerHour
}

// DemoEnabled reports whether OTP demo mode is allowed (env-controlled).
func DemoEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("OTP_DEMO_ENABLED"))) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

// DemoCode returns the fixed demo OTP code (default "123456").
func DemoCode() string {
	v := strings.TrimSpace(os.Getenv("OTP_DEMO_CODE"))
	if ValidateCodeFormat(v) {
		return v
	}
	return "123456"
}

// ClientIP picks a stable client-IP string from a Gin/HTTP request, falling
// back to "" when nothing usable is available. We intentionally ignore X-F-F
// in dev — only the direct RemoteAddr is trusted.
func ClientIP(remoteAddr string) string {
	host, _, err := net.SplitHostPort(strings.TrimSpace(remoteAddr))
	if err == nil && host != "" {
		return host
	}
	return strings.TrimSpace(remoteAddr)
}
