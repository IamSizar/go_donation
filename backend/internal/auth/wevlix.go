// wevlix.go — the OTP delivery client (Wevlix, https://docs.wevlix.com).
//
// Sends the sign-in / confirmation code to a phone over WhatsApp through
// Wevlix's `POST /v1/otp/send`. The code is generated and stored by THIS server
// (the OTP tables decide whether it is right, how long it lives and how many
// tries it gets); Wevlix is only the courier. That is Wevlix's "provided" mode,
// and it is why nothing else in the sign-in flow had to change when the
// delivery provider did.
//
// Configuration (env vars):
//
//	WEVLIX_API_KEY   REQUIRED for real delivery. A project-scoped server key
//	                 ("wvlx_…") with the `otp:send` scope. When unset the OTP
//	                 handler falls back to demo delivery (if OTP_DEMO_ENABLED)
//	                 or refuses to send (502).
//	WEVLIX_BASE_URL  Optional override for the API root, for pointing at a stub
//	                 in tests. Defaults to the live API.
//
// The client is a singleton per AuthHandler — created once at boot and
// re-used. HTTP timeouts are conservative (10s) so a slow gateway never hangs
// the API server.
//
// Free-form SMS (arrival alerts to a section contact) is NOT something Wevlix's
// OTP endpoint can carry, so SendMessage reports ErrOTPUnsupported and callers
// log it rather than failing the payment.

package auth

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	wevlixBaseURL       = "https://api.wevlix.com"
	wevlixHTTPTimeoutMS = 10000
	// The Arabic template is the one the client's users read; Wevlix falls back
	// to another approved template if this locale has none.
	wevlixLocale = "ar"
)

// OTPClient wraps Wevlix's OTP send endpoint. Zero value is unusable — call
// NewOTPClient.
type OTPClient struct {
	apiKey  string
	baseURL string
	http    *http.Client
}

// NewOTPClient reads the WEVLIX_* env vars and returns a ready client, or nil
// if WEVLIX_API_KEY is not set. Callers should check for nil and degrade
// gracefully (demo delivery, or a 502 when real mode is requested).
func NewOTPClient() *OTPClient {
	key := strings.TrimSpace(os.Getenv("WEVLIX_API_KEY"))
	if key == "" {
		return nil
	}
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("WEVLIX_BASE_URL")), "/")
	if base == "" {
		base = wevlixBaseURL
	}
	return &OTPClient{
		apiKey:  key,
		baseURL: base,
		http:    &http.Client{Timeout: time.Duration(wevlixHTTPTimeoutMS) * time.Millisecond},
	}
}

// SendResult is the data the handler cares about after a successful send.
type SendResult struct {
	SmsID           string // Wevlix's tracking id (messageId)
	Cost            int    // unused by Wevlix (billed in USD on their side)
	RemainingCredit int    // unused by Wevlix
	CanCover        bool   // always true on success
}

// Errors the caller may want to distinguish:
var (
	ErrOTPNotConfigured  = errors.New("WEVLIX_API_KEY is not set")
	ErrOTPInsufficient   = errors.New("the Wevlix project cannot cover this send (insufficient balance)")
	ErrOTPBadPhone       = errors.New("Wevlix rejected the phone number format")
	ErrOTPRateLimited    = errors.New("Wevlix rate-limited this project")
	ErrOTPUpstreamFailed = errors.New("Wevlix upstream call failed")
	ErrOTPUnsupported    = errors.New("free-form SMS is not available through Wevlix")
)

// SendVerification sends a 6-digit code to a phone over WhatsApp via Wevlix.
// Returns a SendResult on success (incl. the messageId for tracking) or one of
// the sentinel errors above on failure.
//
// Phone may be in any common form; it is reduced to digits and sent as E.164
// with a leading "+", which is what Wevlix requires.
func (c *OTPClient) SendVerification(ctx context.Context, phone, code string) (*SendResult, error) {
	if c == nil {
		return nil, ErrOTPNotConfigured
	}
	digits := stripToDigits(phone)
	if digits == "" {
		return nil, ErrOTPBadPhone
	}
	// Wevlix accepts 4 or 6 digit codes in provided mode.
	if l := len(code); l != 4 && l != 6 {
		return nil, fmt.Errorf("%w: code must be 4 or 6 digits", ErrOTPUpstreamFailed)
	}

	// Wevlix picks the WhatsApp template by locale and answers 404 when the
	// project has no approved authentication template for the one asked for. The
	// Arabic template is preferred (the users read Arabic), but a missing one
	// must not stop sign-in: fall back to "let Wevlix choose", then to English.
	var lastErr error
	for _, locale := range []string{wevlixLocale, "", "en"} {
		res, err := c.sendOnce(ctx, digits, code, locale)
		if err == nil {
			return res, nil
		}
		lastErr = err
		if !errors.Is(err, errWevlixNoTemplate) {
			return nil, err
		}
	}
	return nil, fmt.Errorf("%w: %v", ErrOTPUpstreamFailed, lastErr)
}

// errWevlixNoTemplate marks Wevlix's 404 "no approved authentication template".
var errWevlixNoTemplate = errors.New("no approved WhatsApp authentication template")

// sendOnce performs one POST /v1/otp/send. An empty locale omits the field.
func (c *OTPClient) sendOnce(ctx context.Context, digits, code, locale string) (*SendResult, error) {
	body := map[string]any{
		"to":              "+" + digits,
		"otpMode":         "provided",
		"code":            code,
		"clientMessageId": newClientMessageID(),
	}
	if locale != "" {
		body["locale"] = locale
	}
	bodyBytes, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal wevlix payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/otp/send", bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("build wevlix request: %w", err)
	}
	req.Header.Set("X-API-Key", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrOTPUpstreamFailed, err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)

	switch resp.StatusCode {
	case http.StatusOK, http.StatusCreated, http.StatusAccepted:
		var parsed struct {
			MessageID string `json:"messageId"`
			Data      struct {
				MessageID string `json:"messageId"`
			} `json:"data"`
		}
		if err := json.Unmarshal(respBody, &parsed); err != nil {
			return nil, fmt.Errorf("decode wevlix success response: %w", err)
		}
		id := parsed.MessageID
		if id == "" {
			id = parsed.Data.MessageID
		}
		return &SendResult{SmsID: id, CanCover: true}, nil

	case http.StatusNotFound:
		msg := extractMessage(respBody)
		if strings.Contains(strings.ToLower(msg), "template") {
			return nil, fmt.Errorf("%w: %s", errWevlixNoTemplate, msg)
		}
		return nil, fmt.Errorf("%w (404): %s", ErrOTPUpstreamFailed, msg)

	case http.StatusBadRequest:
		msg := extractMessage(respBody)
		lower := strings.ToLower(msg)
		switch {
		case strings.Contains(lower, "balance") || strings.Contains(lower, "insufficient"):
			return nil, fmt.Errorf("%w: %s", ErrOTPInsufficient, msg)
		case strings.Contains(lower, "phone") || strings.Contains(lower, "e.164") ||
			strings.Contains(lower, "country") || strings.Contains(lower, "\"to\""):
			return nil, fmt.Errorf("%w: %s", ErrOTPBadPhone, msg)
		}
		return nil, fmt.Errorf("%w (400): %s", ErrOTPUpstreamFailed, msg)

	case http.StatusUnauthorized:
		// Misconfiguration — surface clearly so the key gets fixed.
		return nil, fmt.Errorf("%w: invalid Wevlix API key (401)", ErrOTPNotConfigured)

	case http.StatusForbidden:
		// Key permissions, WhatsApp account state, development-key allow-list or
		// an empty balance all arrive as 403.
		msg := extractMessage(respBody)
		if lower := strings.ToLower(msg); strings.Contains(lower, "balance") || strings.Contains(lower, "insufficient") {
			return nil, fmt.Errorf("%w: %s", ErrOTPInsufficient, msg)
		}
		return nil, fmt.Errorf("%w (403): %s", ErrOTPUpstreamFailed, msg)

	case http.StatusTooManyRequests:
		return nil, fmt.Errorf("%w: %s", ErrOTPRateLimited, extractMessage(respBody))

	default:
		return nil, fmt.Errorf("%w (HTTP %d): %s", ErrOTPUpstreamFailed, resp.StatusCode, extractMessage(respBody))
	}
}

// SendMessage is kept so callers that used to send free-form SMS compile and
// degrade cleanly: Wevlix's OTP endpoint cannot carry arbitrary text.
func (c *OTPClient) SendMessage(ctx context.Context, phone, message string) (*SendResult, error) {
	if c == nil {
		return nil, ErrOTPNotConfigured
	}
	return nil, ErrOTPUnsupported
}

// newClientMessageID returns a unique idempotency key for one send.
func newClientMessageID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("otp_%d", time.Now().UnixNano())
	}
	return "otp_" + hex.EncodeToString(b)
}

// extractMessage pulls a human-readable message out of a Wevlix error body
// (`{"error":{"message":…}}`, `{"message":…}` or `{"error":"…"}`). Best-effort —
// falls back to the raw body when none of those is present.
func extractMessage(body []byte) string {
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		return strings.TrimSpace(string(body))
	}
	if v, ok := m["message"].(string); ok && v != "" {
		return v
	}
	if e, ok := m["error"].(map[string]any); ok {
		if v, ok := e["message"].(string); ok && v != "" {
			return v
		}
	}
	if v, ok := m["error"].(string); ok && v != "" {
		return v
	}
	return strings.TrimSpace(string(body))
}

// stripToDigits keeps only ASCII digits from the input. Used to clean phone
// numbers before they are sent as E.164 ("9647508582031" → "+9647508582031").
func stripToDigits(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}
