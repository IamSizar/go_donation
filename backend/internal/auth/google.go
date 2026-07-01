package auth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// ErrGoogleNotConfigured is returned when GOOGLE_OAUTH_CLIENT_IDS is unset — the
// Google sign-in code is wired but needs real client IDs before it can run.
var ErrGoogleNotConfigured = errors.New("google sign-in not configured")

// GoogleClaims is the subset of a verified Google ID token we care about.
type GoogleClaims struct {
	Sub           string
	Email         string
	EmailVerified bool
	Name          string
	Picture       string
}

// googleAllowedAudiences reads the comma-separated GOOGLE_OAUTH_CLIENT_IDS env
// (the Web + iOS + Android OAuth client IDs whose tokens we accept).
func googleAllowedAudiences() []string {
	raw := strings.TrimSpace(os.Getenv("GOOGLE_OAUTH_CLIENT_IDS"))
	if raw == "" {
		return nil
	}
	var out []string
	for _, p := range strings.Split(raw, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// GoogleConfigured reports whether Google sign-in has client IDs configured.
func GoogleConfigured() bool { return len(googleAllowedAudiences()) > 0 }

var googleHTTP = &http.Client{Timeout: 8 * time.Second}

// VerifyGoogleIDToken validates a Google ID token via Google's tokeninfo
// endpoint (which verifies the signature and expiry server-side), then enforces
// the issuer, audience, and subject locally. No extra dependency required.
func VerifyGoogleIDToken(ctx context.Context, idToken string) (*GoogleClaims, error) {
	idToken = strings.TrimSpace(idToken)
	if idToken == "" {
		return nil, errors.New("empty id_token")
	}
	auds := googleAllowedAudiences()
	if len(auds) == 0 {
		return nil, ErrGoogleNotConfigured
	}

	endpoint := "https://oauth2.googleapis.com/tokeninfo?id_token=" + url.QueryEscape(idToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	resp, err := googleHTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("google tokeninfo: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, errors.New("invalid Google token")
	}

	var ti struct {
		Aud           string `json:"aud"`
		Sub           string `json:"sub"`
		Email         string `json:"email"`
		EmailVerified string `json:"email_verified"` // tokeninfo returns "true"/"false"
		Name          string `json:"name"`
		Picture       string `json:"picture"`
		Iss           string `json:"iss"`
		Exp           string `json:"exp"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&ti); err != nil {
		return nil, err
	}

	if ti.Iss != "accounts.google.com" && ti.Iss != "https://accounts.google.com" {
		return nil, errors.New("unexpected token issuer")
	}
	audOK := false
	for _, a := range auds {
		if a == ti.Aud {
			audOK = true
			break
		}
	}
	if !audOK {
		return nil, errors.New("token audience mismatch")
	}
	// Defensive expiry check (tokeninfo already rejects expired tokens).
	if exp, perr := strconv.ParseInt(ti.Exp, 10, 64); perr == nil && time.Now().Unix() >= exp {
		return nil, errors.New("token expired")
	}
	if ti.Sub == "" {
		return nil, errors.New("token missing subject")
	}

	return &GoogleClaims{
		Sub:           ti.Sub,
		Email:         strings.ToLower(strings.TrimSpace(ti.Email)),
		EmailVerified: ti.EmailVerified == "true",
		Name:          strings.TrimSpace(ti.Name),
		Picture:       strings.TrimSpace(ti.Picture),
	}, nil
}
