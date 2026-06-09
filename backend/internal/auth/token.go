package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	tokenTTL            = 30 * 24 * time.Hour // 30 days, matches PHP API_ACCESS_TOKEN_TTL_SECONDS
	tokenSelectorBytes  = 9                   // → 18 hex chars
	tokenSecretBytes    = 32                  // → 64 hex chars
	tokenSelectorHexLen = tokenSelectorBytes * 2
	tokenSecretHexLen   = tokenSecretBytes * 2
)

// Session is the public token response, matching the PHP api_auth_issue_token() shape.
type Session struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresAt   string `json:"expires_at"` // "YYYY-MM-DD HH:MM:SS" UTC, matches PHP gmdate()
	ExpiresIn   int    `json:"expires_in"` // seconds
}

// ResolvedUser is what middleware attaches to the request context after Bearer auth.
type ResolvedUser struct {
	TokenID            int64
	UserID             int64
	RoleID             int
	Active             int
	IsAdmin            int
	Phone              string
	CreatedAt          time.Time
	RegistrationStatus string // incomplete | pending | approved | rejected
}

type TokenStore struct {
	Pool *pgxpool.Pool
}

func NewTokenStore(pool *pgxpool.Pool) *TokenStore {
	return &TokenStore{Pool: pool}
}

// IssueToken mints a new token for the user and stores its hash.
// Format: "<selector>.<secret>" — only the SHA-256 hash of the secret is stored.
func (s *TokenStore) IssueToken(ctx context.Context, userID int64, userAgent, ip string) (Session, error) {
	selector, err := randHex(tokenSelectorBytes)
	if err != nil {
		return Session{}, fmt.Errorf("gen selector: %w", err)
	}
	secret, err := randHex(tokenSecretBytes)
	if err != nil {
		return Session{}, fmt.Errorf("gen secret: %w", err)
	}
	hash := sha256Hex(secret)
	expiresAt := time.Now().UTC().Add(tokenTTL)

	if len(userAgent) > 255 {
		userAgent = userAgent[:255]
	}
	if len(ip) > 45 {
		ip = ip[:45]
	}

	_, err = s.Pool.Exec(ctx,
		`INSERT INTO api_access_tokens
		   (user_id, token_selector, token_hash, user_agent, ip_address, expires_at)
		 VALUES ($1, $2, $3, NULLIF($4, ''), NULLIF($5, ''), $6)`,
		userID, selector, hash, userAgent, ip, expiresAt,
	)
	if err != nil {
		return Session{}, fmt.Errorf("insert token: %w", err)
	}

	return Session{
		AccessToken: selector + "." + secret,
		TokenType:   "Bearer",
		ExpiresAt:   expiresAt.Format("2006-01-02 15:04:05"),
		ExpiresIn:   int(tokenTTL.Seconds()),
	}, nil
}

// ResolveToken validates a "<selector>.<secret>" token and returns the resolved user.
// Returns nil (no error) when the token is missing/invalid/expired/revoked.
func (s *TokenStore) ResolveToken(ctx context.Context, raw string) (*ResolvedUser, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}
	parts := strings.SplitN(raw, ".", 2)
	if len(parts) != 2 {
		return nil, nil
	}
	selector, secret := parts[0], parts[1]
	if len(selector) != tokenSelectorHexLen || len(secret) != tokenSecretHexLen {
		return nil, nil
	}
	if !isHex(selector) || !isHex(secret) {
		return nil, nil
	}

	providedHash := sha256Hex(secret)

	var (
		tokenID    int64
		userID     int64
		storedHash string
		expiresAt  time.Time
		revokedAt  *time.Time
		roleID     *int
		active     *int
		isAdmin    *int
		phone      string
		createdAt  time.Time
		regStatus  *string
	)
	err := s.Pool.QueryRow(ctx,
		`SELECT t.id, t.user_id, t.token_hash, t.expires_at, t.revoked_at,
		        u.role_id, u.active, u.is_admin, u.phone, u.created_at, u.registration_status
		   FROM api_access_tokens t
		   JOIN users u ON u.id = t.user_id
		  WHERE t.token_selector = $1
		  LIMIT 1`,
		selector,
	).Scan(&tokenID, &userID, &storedHash, &expiresAt, &revokedAt, &roleID, &active, &isAdmin, &phone, &createdAt, &regStatus)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// Constant-time dummy compare to keep timing flat.
			_ = subtle.ConstantTimeCompare([]byte(strings.Repeat("0", 64)), []byte(providedHash))
			return nil, nil
		}
		return nil, fmt.Errorf("lookup token: %w", err)
	}

	if revokedAt != nil {
		return nil, nil
	}
	if time.Now().After(expiresAt) {
		return nil, nil
	}
	if subtle.ConstantTimeCompare([]byte(storedHash), []byte(providedHash)) != 1 {
		return nil, nil
	}

	// Best-effort last_used_at touch; failure should not block auth.
	_, _ = s.Pool.Exec(ctx,
		`UPDATE api_access_tokens SET last_used_at = NOW() WHERE id = $1`, tokenID)

	r := &ResolvedUser{
		TokenID:   tokenID,
		UserID:    userID,
		Phone:     phone,
		CreatedAt: createdAt,
	}
	if regStatus != nil {
		r.RegistrationStatus = *regStatus
	}
	if roleID != nil {
		r.RoleID = *roleID
	}
	if active != nil {
		r.Active = *active
	}
	if isAdmin != nil {
		r.IsAdmin = *isAdmin
	}
	return r, nil
}

// RevokeToken marks a token's row as revoked (if it exists and is not already revoked).
func (s *TokenStore) RevokeToken(ctx context.Context, raw string) error {
	parts := strings.SplitN(strings.TrimSpace(raw), ".", 2)
	if len(parts) != 2 || parts[0] == "" {
		return nil
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE api_access_tokens SET revoked_at = NOW()
		  WHERE token_selector = $1 AND revoked_at IS NULL`,
		parts[0],
	)
	return err
}

func randHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func sha256Hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func isHex(s string) bool {
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9':
		case c >= 'a' && c <= 'f':
		case c >= 'A' && c <= 'F':
		default:
			return false
		}
	}
	return true
}
