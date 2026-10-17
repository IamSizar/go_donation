package handlers

import (
	"net/http"
	"testing"
)

// The create-account screen must hear "already registered" BEFORE a code is
// spent. Only that screen asks (purpose=signup): every other caller needs a
// code for a number that already exists.
func TestSignupOTPRequestRefusesAnAlreadyRegisteredNumber(t *testing.T) {
	pool := newAuthTestPool(t)
	t.Setenv("OTP_DEMO_ENABLED", "1")
	t.Setenv("OTP_DEMO_CODE", "424242")
	r := newAuthRouter(t, pool)

	withPassword := insertAccount(t, pool, "user", "a-real-password-1")
	status, body := postJSON(t, r, "/api/auth/otp/request",
		map[string]any{"phone": withPassword.phone, "mode": "demo", "purpose": "signup"})
	if status != http.StatusConflict || body["code"] != "phone_already_registered" {
		t.Fatalf("finished account on sign-up: status=%d body=%v, want 409 phone_already_registered", status, body)
	}

	// The same number still gets a code from every other screen (sign-in
	// recovery, staff login): no purpose, no refusal.
	status, body = postJSON(t, r, "/api/auth/otp/request",
		map[string]any{"phone": withPassword.phone, "mode": "demo"})
	if status != http.StatusOK {
		t.Fatalf("no purpose: status=%d body=%v, want 200", status, body)
	}

	// An older account that never set a password needs a code to set one.
	noPassword := insertAccount(t, pool, "user", "")
	status, body = postJSON(t, r, "/api/auth/otp/request",
		map[string]any{"phone": noPassword.phone, "mode": "demo", "purpose": "signup"})
	if status != http.StatusOK {
		t.Fatalf("account without a password on sign-up: status=%d body=%v, want 200", status, body)
	}

	// A number nobody has registered signs up normally.
	status, body = postJSON(t, r, "/api/auth/otp/request",
		map[string]any{"phone": randomTestPhone(), "mode": "demo", "purpose": "signup"})
	if status != http.StatusOK {
		t.Fatalf("new number on sign-up: status=%d body=%v, want 200", status, body)
	}
}
