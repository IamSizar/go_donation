package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func newTestWevlix(t *testing.T, status int, reply string, seen *map[string]any, hdr *http.Header, path *string) *OTPClient {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if seen != nil {
			_ = json.NewDecoder(r.Body).Decode(seen)
		}
		if hdr != nil {
			*hdr = r.Header.Clone()
		}
		if path != nil {
			*path = r.URL.Path
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(reply))
	}))
	t.Cleanup(srv.Close)
	t.Setenv("WEVLIX_API_KEY", "wvlx_test")
	t.Setenv("WEVLIX_BASE_URL", srv.URL)
	return NewOTPClient()
}

func TestNewOTPClientNeedsTheKey(t *testing.T) {
	t.Setenv("WEVLIX_API_KEY", "")
	if NewOTPClient() != nil {
		t.Fatal("client must be nil without WEVLIX_API_KEY so demo/real selection keeps working")
	}
}

func TestSendVerificationSendsOurOwnCodeAsE164(t *testing.T) {
	var body map[string]any
	var hdr http.Header
	var path string
	c := newTestWevlix(t, 200, `{"messageId":"m-1","status":"queued"}`, &body, &hdr, &path)

	res, err := c.SendVerification(context.Background(), "964 750-123 4567", "123456")
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if res.SmsID != "m-1" {
		t.Errorf("tracking id = %q, want m-1", res.SmsID)
	}
	if path != "/v1/otp/send" {
		t.Errorf("path = %q", path)
	}
	if hdr.Get("X-API-Key") != "wvlx_test" {
		t.Errorf("X-API-Key header missing")
	}
	if body["to"] != "+9647501234567" {
		t.Errorf("to = %v, want E.164 with +", body["to"])
	}
	if body["otpMode"] != "provided" || body["code"] != "123456" {
		t.Errorf("must hand Wevlix OUR code in provided mode, got %v", body)
	}
	if body["clientMessageId"] == "" || body["clientMessageId"] == nil {
		t.Errorf("clientMessageId (idempotency key) missing")
	}
}

func TestSendVerificationMapsErrors(t *testing.T) {
	cases := []struct {
		name   string
		status int
		reply  string
		want   error
	}{
		{"bad key", 401, `{"error":{"message":"invalid"}}`, ErrOTPNotConfigured},
		{"no balance", 403, `{"error":{"message":"project balance is insufficient"}}`, ErrOTPInsufficient},
		{"other 403", 403, `{"error":{"message":"WhatsApp Business Account is not active"}}`, ErrOTPUpstreamFailed},
		{"bad number", 400, `{"error":{"message":"to must be E.164 phone"}}`, ErrOTPBadPhone},
		{"rate limit", 429, `{"message":"slow down"}`, ErrOTPRateLimited},
		{"server error", 500, `oops`, ErrOTPUpstreamFailed},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestWevlix(t, tc.status, tc.reply, nil, nil, nil)
			_, err := c.SendVerification(context.Background(), "9647501234567", "123456")
			if !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
}

func TestFreeFormSMSIsReportedUnsupported(t *testing.T) {
	c := newTestWevlix(t, 200, `{}`, nil, nil, nil)
	if _, err := c.SendMessage(context.Background(), "9647501234567", "hello"); !errors.Is(err, ErrOTPUnsupported) {
		t.Fatalf("err = %v, want ErrOTPUnsupported", err)
	}
}
