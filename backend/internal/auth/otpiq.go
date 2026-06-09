// otpiq.go — thin OTPIQ client used by the OTP-request handler.
//
// Phase 19. Sends verification codes via OTPIQ's `POST /sms` endpoint
// (https://docs.otpiq.com/api-reference/openapi.json) using the
// "whatsapp-sms" provider so we try WhatsApp first and fall back to SMS
// automatically if WhatsApp delivery fails. That's the cheapest/fastest
// path for users that have WhatsApp installed and a robust fallback for
// those who don't.
//
// Configuration (env vars):
//
//	OTPIQ_API_KEY    REQUIRED for real-mode delivery. Format: sk_live_… or sk_test_…
//	                 When unset, the OTP handler refuses to send real codes (502).
//	OTPIQ_PROVIDER   Optional. Defaults to "whatsapp-sms" per product decision.
//	                 Any of: auto, sms, whatsapp, telegram, whatsapp-sms,
//	                 telegram-sms, whatsapp-telegram-sms.
//	OTPIQ_SENDER_ID  Optional sender id (max 11 chars). Falls back to OTPIQ's
//	                 default sender when unset.
//
// The client is a singleton per AuthHandler — created once at boot and
// re-used. HTTP timeouts are conservative (10s) so a flaky OTPIQ never
// hangs the API server.

package auth

import (
	"bytes"
	"context"
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
	otpiqBaseURL       = "https://api.otpiq.com/api"
	otpiqDefaultProv   = "whatsapp-sms" // WhatsApp first, SMS as fallback (product decision)
	otpiqHTTPTimeoutMS = 10000
)

// OTPIQClient wraps the POST /sms endpoint. Zero value is unusable — call
// NewOTPIQClient.
type OTPIQClient struct {
	apiKey   string
	provider string
	senderID string
	http     *http.Client
}

// NewOTPIQClient reads OTPIQ_* env vars and returns a ready client, or nil
// if OTPIQ_API_KEY is not set. Callers should check for nil and degrade
// gracefully (e.g. return 502 when the user requests real-mode OTP).
func NewOTPIQClient() *OTPIQClient {
	key := strings.TrimSpace(os.Getenv("OTPIQ_API_KEY"))
	if key == "" {
		return nil
	}
	provider := strings.TrimSpace(os.Getenv("OTPIQ_PROVIDER"))
	if provider == "" {
		provider = otpiqDefaultProv
	}
	return &OTPIQClient{
		apiKey:   key,
		provider: provider,
		senderID: strings.TrimSpace(os.Getenv("OTPIQ_SENDER_ID")),
		http:     &http.Client{Timeout: time.Duration(otpiqHTTPTimeoutMS) * time.Millisecond},
	}
}

// SendResult is the data the handler cares about after a successful send.
type SendResult struct {
	SmsID           string // OTPIQ's tracking id (sms-XXXX…)
	Cost            int    // request cost in IQD
	RemainingCredit int    // OTPIQ account balance after the send
	CanCover        bool   // false when the account couldn't cover; we still treat as success
}

// Errors the caller may want to distinguish:
var (
	ErrOTPIQNotConfigured  = errors.New("OTPIQ_API_KEY is not set")
	ErrOTPIQInsufficient   = errors.New("OTPIQ account cannot cover this send (insufficient credit)")
	ErrOTPIQBadPhone       = errors.New("OTPIQ rejected the phone number format")
	ErrOTPIQRateLimited    = errors.New("OTPIQ rate-limited this account")
	ErrOTPIQUpstreamFailed = errors.New("OTPIQ upstream call failed")
)

// SendVerification sends a 6-digit code to a phone via OTPIQ's verification
// flow. Returns a SendResult on success (incl. sms_id for tracking) or one
// of the sentinel errors above on failure.
//
// Phone is expected in international format WITHOUT a leading +
// (e.g. 9647508582031), matching OTPIQ's spec.
func (c *OTPIQClient) SendVerification(ctx context.Context, phone, code string) (*SendResult, error) {
	if c == nil {
		return nil, ErrOTPIQNotConfigured
	}

	// Strip any leading + and any non-digit so we always send what OTPIQ wants.
	cleanPhone := stripToDigits(phone)
	if cleanPhone == "" {
		return nil, ErrOTPIQBadPhone
	}

	body := map[string]any{
		"phoneNumber":      cleanPhone,
		"smsType":          "verification",
		"verificationCode": code,
		"provider":         c.provider,
	}
	if c.senderID != "" {
		body["senderId"] = c.senderID
	}

	bodyBytes, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal otpiq payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		otpiqBaseURL+"/sms", bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("build otpiq request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrOTPIQUpstreamFailed, err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	switch resp.StatusCode {
	case http.StatusOK, http.StatusCreated:
		var parsed struct {
			SmsID           string `json:"smsId"`
			Cost            int    `json:"cost"`
			RemainingCredit int    `json:"remainingCredit"`
			CanCover        bool   `json:"canCover"`
		}
		if err := json.Unmarshal(respBody, &parsed); err != nil {
			return nil, fmt.Errorf("decode otpiq success response: %w", err)
		}
		return &SendResult{
			SmsID:           parsed.SmsID,
			Cost:            parsed.Cost,
			RemainingCredit: parsed.RemainingCredit,
			CanCover:        parsed.CanCover,
		}, nil

	case http.StatusBadRequest:
		// Inspect the message — OTPIQ surfaces credit/phone/route problems
		// here so we map them to actionable sentinel errors.
		msg := extractMessage(respBody)
		lower := strings.ToLower(msg)
		switch {
		case strings.Contains(lower, "insufficient") || strings.Contains(lower, "credit"):
			return nil, fmt.Errorf("%w: %s", ErrOTPIQInsufficient, msg)
		case strings.Contains(lower, "phone") || strings.Contains(lower, "invalid number"):
			return nil, fmt.Errorf("%w: %s", ErrOTPIQBadPhone, msg)
		}
		return nil, fmt.Errorf("%w (400): %s", ErrOTPIQUpstreamFailed, msg)

	case http.StatusUnauthorized:
		// Treat as misconfiguration — surface clearly so admin fixes the key.
		return nil, fmt.Errorf("%w: invalid OTPIQ API key (401)", ErrOTPIQNotConfigured)

	case http.StatusTooManyRequests:
		return nil, fmt.Errorf("%w: %s", ErrOTPIQRateLimited, extractMessage(respBody))

	default:
		return nil, fmt.Errorf("%w (HTTP %d): %s",
			ErrOTPIQUpstreamFailed, resp.StatusCode, extractMessage(respBody))
	}
}

// extractMessage pulls the `message` (or `error`) field out of an OTPIQ
// error body. Best-effort — falls back to the raw body when neither key
// is present.
func extractMessage(body []byte) string {
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		return strings.TrimSpace(string(body))
	}
	if v, ok := m["message"].(string); ok && v != "" {
		return v
	}
	if v, ok := m["error"].(string); ok && v != "" {
		return v
	}
	return strings.TrimSpace(string(body))
}

// stripToDigits keeps only ASCII digits from the input. Used to clean
// phone numbers before sending to OTPIQ (it wants e.g. "9647508582031").
func stripToDigits(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}
