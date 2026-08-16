// admin_main_admin_guard_test.go — can the main admin's account still be
// rewritten in one request by whoever holds a peer session (H20)?
//
// # WHAT THESE TESTS PIN
//
// The client asked that a change to the main-admin account happen "only via a
// confirmation code sent through BOTH phone and email". Four rules follow, and
// each is one case below:
//
//   - With no email channel configured — the state of every environment today —
//     a credential change to a super_admin is REFUSED, and the stored row is
//     unchanged. This is the whole fail-closed decision, and it is the case
//     that fails loudest if the gate is ever removed.
//   - With both channels live, the change takes TWO requests: the first sends
//     one code to the phone AND to the email and applies nothing; the second
//     carries the code and applies. Both stubs must have seen the same code.
//   - A wrong code changes nothing and burns an attempt.
//   - The carve-outs hold: an ORDINARY user's phone is still editable with no
//     confirmation at all, and SUSPENDING a main admin — the containment action
//     used when that account is believed compromised — is not behind a code
//     delivered to the compromised account's own phone and mailbox.
//
// # HOW REAL THESE ARE
//
// Nothing about the request chain is stubbed: RequireAdmin resolves a genuine
// token, the handler is the deployed one, and the confirmation row is read back
// out of Postgres. The only doubles are the two OUTBOUND gateways — a real
// SMTP conversation against a listener on 127.0.0.1, and OTPIQ pointed at a
// local HTTP stub through OTPIQ_BASE_URL, which is the seam the repo already
// uses for exactly this. No message leaves the machine.
//
// Needs a throwaway Postgres; skipped unless TEST_DATABASE_URL is set:
//
//	createdb godonation_h20
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_h20?sslmode=disable' \
//	  go test ./internal/handlers/ -run MainAdmin -v
package handlers

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// ─── Harness ────────────────────────────────────────────────────────────

// fakeSMTP is a minimal RFC 5321 server on 127.0.0.1. It speaks just enough of
// the protocol for net/smtp to complete a delivery, and records the body it was
// handed so a test can prove the code actually travelled by email rather than
// merely that Send returned nil.
type fakeSMTP struct {
	listener net.Listener
	mu       sync.Mutex
	bodies   []string
}

func newFakeSMTP(t *testing.T) *fakeSMTP {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	s := &fakeSMTP{listener: ln}
	go s.serve()
	t.Cleanup(func() { _ = ln.Close() })
	return s
}

func (s *fakeSMTP) port() int { return s.listener.Addr().(*net.TCPAddr).Port }

func (s *fakeSMTP) serve() {
	for {
		conn, err := s.listener.Accept()
		if err != nil {
			return
		}
		go s.handle(conn)
	}
}

func (s *fakeSMTP) handle(conn net.Conn) {
	defer func() { _ = conn.Close() }()
	r := bufio.NewReader(conn)
	write := func(line string) { _, _ = conn.Write([]byte(line + "\r\n")) }
	write("220 fake.local ESMTP")
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return
		}
		cmd := strings.ToUpper(strings.TrimSpace(line))
		switch {
		case strings.HasPrefix(cmd, "EHLO"), strings.HasPrefix(cmd, "HELO"):
			// A bare 250 advertises no extensions — in particular no STARTTLS,
			// which is exactly the shape the mailer must refuse to send
			// CREDENTIALS over and is happy to use when there are none.
			write("250 fake.local")
		case strings.HasPrefix(cmd, "MAIL FROM"), strings.HasPrefix(cmd, "RCPT TO"):
			write("250 OK")
		case strings.HasPrefix(cmd, "DATA"):
			write("354 End data with <CR><LF>.<CR><LF>")
			var body strings.Builder
			for {
				l, err := r.ReadString('\n')
				if err != nil {
					return
				}
				if strings.TrimRight(l, "\r\n") == "." {
					break
				}
				body.WriteString(l)
			}
			s.mu.Lock()
			s.bodies = append(s.bodies, body.String())
			s.mu.Unlock()
			write("250 OK")
		case strings.HasPrefix(cmd, "QUIT"):
			write("221 Bye")
			return
		default:
			write("250 OK")
		}
	}
}

// decodedBodies returns the base64 message bodies as readable UTF-8, which is
// how a test finds the six-digit code inside an Arabic message.
func (s *fakeSMTP) decodedBodies() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]string, 0, len(s.bodies))
	for _, raw := range s.bodies {
		_, b64, found := strings.Cut(raw, "\r\n\r\n")
		if !found {
			out = append(out, raw)
			continue
		}
		dec, err := base64.StdEncoding.DecodeString(strings.ReplaceAll(strings.TrimSpace(b64), "\r\n", ""))
		if err != nil {
			out = append(out, raw)
			continue
		}
		out = append(out, string(dec))
	}
	return out
}

// fakeOTPIQ stands in for the SMS gateway, recording every verificationCode it
// is asked to deliver.
type fakeOTPIQ struct {
	server *httptest.Server
	mu     sync.Mutex
	codes  []string
}

func newFakeOTPIQ(t *testing.T) *fakeOTPIQ {
	t.Helper()
	f := &fakeOTPIQ{}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			VerificationCode string `json:"verificationCode"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		f.mu.Lock()
		f.codes = append(f.codes, body.VerificationCode)
		f.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"smsId":"sms-test","cost":1,"remainingCredit":99,"canCover":true}`))
	}))
	t.Cleanup(f.server.Close)
	return f
}

func (f *fakeOTPIQ) sent() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.codes...)
}

// setEmail puts an address on a test account. insertAccount leaves users.email
// NULL, which is the production shape, so a test about the EMAIL CHANNEL has to
// say so explicitly.
func setEmail(t *testing.T, pool *pgxpool.Pool, userID int64, email string) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`UPDATE users SET email = $1 WHERE id = $2`, email, userID); err != nil {
		t.Fatalf("set email on user %d: %v", userID, err)
	}
}

func storedPhone(t *testing.T, pool *pgxpool.Pool, userID int64) string {
	t.Helper()
	var phone *string
	if err := pool.QueryRow(context.Background(),
		`SELECT phone FROM users WHERE id = $1`, userID).Scan(&phone); err != nil {
		t.Fatalf("read phone of user %d: %v", userID, err)
	}
	if phone == nil {
		return ""
	}
	return *phone
}

// newUserWriteRouter wires the two routes H20 touches exactly as main.go does,
// with the guard built from whichever gateways the test supplies. Passing nil
// for both is the production shape today: no SMTP, no OTPIQ.
func newUserWriteRouter(pool *pgxpool.Pool, mailer *auth.Mailer, otpiq *auth.OTPIQClient) *gin.Engine {
	gin.SetMode(gin.TestMode)
	tokens := auth.NewTokenStore(pool)
	guard := NewMainAdminConfirm(pool, otpiq, mailer)

	editH := NewAdminEditHandler(pool)
	editH.MainAdmin = guard
	statusH := NewAdminStatusHandler(pool, nil, nil, nil)
	statusH.MainAdmin = guard

	r := gin.New()
	r.PATCH("/api/admin/users/:id", auth.RequireAdmin(tokens), editH.User)
	r.POST("/api/admin/users/:id/account_status", auth.RequireAdmin(tokens), statusH.UserAccountStatus)
	return r
}

// callAs drives one authenticated request and returns the status and decoded body.
func callAs(
	t *testing.T, pool *pgxpool.Pool, r *gin.Engine,
	method, path string, actorID int64, body map[string]any,
) (int, map[string]any) {
	t.Helper()
	session, err := auth.NewTokenStore(pool).IssueToken(
		context.Background(), actorID, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("issue token for actor %d: %v", actorID, err)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec.Code, decoded
}

func userPath(id int64, suffix string) string {
	return "/api/admin/users/" + strconv.FormatInt(id, 10) + suffix
}

// liveGateways builds a guard whose two channels both reach local stubs, and
// returns the router plus the stubs so a test can read what was delivered.
func liveGateways(t *testing.T, pool *pgxpool.Pool) (*gin.Engine, *fakeSMTP, *fakeOTPIQ) {
	t.Helper()
	smtpStub := newFakeSMTP(t)
	otpiqStub := newFakeOTPIQ(t)
	t.Setenv("OTPIQ_API_KEY", "sk_test_fake")
	t.Setenv("OTPIQ_BASE_URL", otpiqStub.server.URL)
	mailer := auth.NewMailer(auth.MailerConfig{
		Host: "127.0.0.1", Port: smtpStub.port(), From: "no-reply@test.local",
	})
	if mailer == nil {
		t.Fatal("NewMailer returned nil for a fully configured mailer")
	}
	return newUserWriteRouter(pool, mailer, auth.NewOTPIQClient()), smtpStub, otpiqStub
}

// codeFrom pulls the six-digit code out of a delivered message body.
func codeFrom(t *testing.T, body string) string {
	t.Helper()
	for _, field := range strings.Fields(body) {
		trimmed := strings.Trim(field, ".،\n\r")
		if len(trimmed) == 6 && auth.ValidateCodeFormat(trimmed) {
			return trimmed
		}
	}
	t.Fatalf("no 6-digit code found in delivered message: %q", body)
	return ""
}

// ─── The boundary ───────────────────────────────────────────────────────

// TestMainAdminChangeRefusedWhenEmailUnavailable is the production shape today
// and the reason this feature exists: SMTP_* unset, OTPIQ_API_KEY unset.
//
// The change must be REFUSED and the row must be untouched. A version of this
// feature that let the write through "with a warning" would pass every other
// test in this file and fail this one.
func TestMainAdminChangeRefusedWhenEmailUnavailable(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "super_admin", "")
	setEmail(t, pool, target.id, "owner@example.org")
	before := storedPhone(t, pool, target.id)

	r := newUserWriteRouter(pool, nil, nil) // no email channel, no SMS channel
	status, body := callAs(t, pool, r, http.MethodPatch, userPath(target.id, ""), actor.id,
		map[string]any{"phone": "9647700000001"})

	if status != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want 503 (body: %v)", status, body)
	}
	if got, _ := body["code"].(string); got != "main_admin_email_unavailable" {
		t.Errorf("code = %q, want main_admin_email_unavailable (body: %v)", got, body)
	}
	if after := storedPhone(t, pool, target.id); after != before {
		t.Errorf("the main admin's sign-in number was rewritten to %q with NO confirmation sent "+
			"— the two-channel gate did not hold", after)
	}
}

// TestMainAdminChangeNeedsBothChannels is the happy path, and it asserts the
// word the client actually used: BOTH.
func TestMainAdminChangeNeedsBothChannels(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "super_admin", "")
	setEmail(t, pool, target.id, "owner@example.org")
	before := storedPhone(t, pool, target.id)
	newPhone := "9647700000002"

	r, smtpStub, otpiqStub := liveGateways(t, pool)

	// First call: no code. Nothing may be applied.
	status, body := callAs(t, pool, r, http.MethodPatch, userPath(target.id, ""), actor.id,
		map[string]any{"phone": newPhone})
	if status != statusConfirmationRequired {
		t.Fatalf("first call status = %d, want %d (body: %v)", status, statusConfirmationRequired, body)
	}
	if got, _ := body["code"].(string); got != "main_admin_confirmation_required" {
		t.Fatalf("first call code = %q, want main_admin_confirmation_required", got)
	}
	if after := storedPhone(t, pool, target.id); after != before {
		t.Fatalf("the phone changed on the FIRST call — the code is decorative")
	}

	emails := smtpStub.decodedBodies()
	texts := otpiqStub.sent()
	if len(emails) != 1 {
		t.Fatalf("emails delivered = %d, want 1", len(emails))
	}
	if len(texts) != 1 {
		t.Fatalf("SMS delivered = %d, want 1", len(texts))
	}
	emailCode := codeFrom(t, emails[0])
	if texts[0] != emailCode {
		t.Errorf("the SMS carried %q and the email carried %q — the two channels must confirm ONE change",
			texts[0], emailCode)
	}
	// The message must never be the value being confirmed, only a code.
	if strings.Contains(emails[0], newPhone) {
		t.Errorf("the confirmation email leaked the new phone number")
	}

	// Second call: with the code, the change applies.
	status, body = callAs(t, pool, r, http.MethodPatch, userPath(target.id, ""), actor.id,
		map[string]any{"phone": newPhone, "confirmation_code": emailCode})
	if status != http.StatusOK {
		t.Fatalf("second call status = %d, want 200 (body: %v)", status, body)
	}
	if after := storedPhone(t, pool, target.id); after != newPhone {
		t.Errorf("phone = %q after a confirmed change, want %q", after, newPhone)
	}

	// The stored record is the evidence that two channels were used.
	var phoneSent, emailSent, consumed *string
	if err := pool.QueryRow(context.Background(),
		`SELECT phone_sent_at::text, email_sent_at::text, consumed_at::text
		   FROM admin_change_confirmations
		  WHERE target_user_id = $1 ORDER BY id DESC LIMIT 1`,
		target.id).Scan(&phoneSent, &emailSent, &consumed); err != nil {
		t.Fatalf("read confirmation row: %v", err)
	}
	if phoneSent == nil || emailSent == nil {
		t.Errorf("confirmation row records phone_sent_at=%v email_sent_at=%v — both must be set", phoneSent, emailSent)
	}
	if consumed == nil {
		t.Errorf("the confirmation was not consumed — the same code could be replayed")
	}

	// Replay: the same code must not work twice.
	status, _ = callAs(t, pool, r, http.MethodPatch, userPath(target.id, ""), actor.id,
		map[string]any{"phone": "9647700000003", "confirmation_code": emailCode})
	if status == http.StatusOK {
		t.Errorf("a spent confirmation code was accepted a second time")
	}
}

// TestMainAdminWrongCodeChangesNothing — a guess must cost an attempt and leave
// the account exactly as it was.
func TestMainAdminWrongCodeChangesNothing(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "super_admin", "")
	setEmail(t, pool, target.id, "owner@example.org")
	before := storedPhone(t, pool, target.id)

	r, _, _ := liveGateways(t, pool)
	if status, body := callAs(t, pool, r, http.MethodPatch, userPath(target.id, ""), actor.id,
		map[string]any{"phone": "9647700000004"}); status != statusConfirmationRequired {
		t.Fatalf("challenge status = %d, want %d (body: %v)", status, statusConfirmationRequired, body)
	}

	status, body := callAs(t, pool, r, http.MethodPatch, userPath(target.id, ""), actor.id,
		map[string]any{"phone": "9647700000004", "confirmation_code": "000000"})
	if status != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401 (body: %v)", status, body)
	}
	if after := storedPhone(t, pool, target.id); after != before {
		t.Errorf("phone changed to %q on a WRONG code", after)
	}
	var attempts int
	if err := pool.QueryRow(context.Background(),
		`SELECT attempts FROM admin_change_confirmations
		  WHERE target_user_id = $1 ORDER BY id DESC LIMIT 1`, target.id).Scan(&attempts); err != nil {
		t.Fatalf("read attempts: %v", err)
	}
	if attempts != 1 {
		t.Errorf("attempts = %d after one wrong guess, want 1 — the guess budget is not being spent", attempts)
	}
}

// TestOrdinaryUserEditNeedsNoConfirmation pins the blast radius. Correcting a
// beneficiary's mistyped number is an everyday task; if H20 reached it, the
// feature would have made the dashboard unusable to buy protection for four
// fields on one tier.
func TestOrdinaryUserEditNeedsNoConfirmation(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "user", "")
	newPhone := "9647700000005"

	r := newUserWriteRouter(pool, nil, nil) // no channels at all, as in production
	status, body := callAs(t, pool, r, http.MethodPatch, userPath(target.id, ""), actor.id,
		map[string]any{"phone": newPhone})
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — an ordinary user's phone must stay editable (body: %v)", status, body)
	}
	if after := storedPhone(t, pool, target.id); after != newPhone {
		t.Errorf("phone = %q, want %q", after, newPhone)
	}
}

// TestMainAdminContainmentStaysOpen is the carve-out, and it is a security
// property rather than a convenience: suspending a main-admin account is what
// you do when you believe it is COMPROMISED. Putting that behind a code
// delivered to the compromised account's own phone and mailbox would give the
// attacker a veto over their own removal.
func TestMainAdminContainmentStaysOpen(t *testing.T) {
	pool := newAuthTestPool(t)
	actor := insertAccount(t, pool, "super_admin", "")
	target := insertAccount(t, pool, "super_admin", "")
	setEmail(t, pool, target.id, "owner@example.org")

	r := newUserWriteRouter(pool, nil, nil) // no channels — must not matter here
	status, body := callAs(t, pool, r, http.MethodPost,
		userPath(target.id, "/account_status"), actor.id, map[string]any{"status": "suspended"})
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 — a compromised main admin must remain suspendable (body: %v)", status, body)
	}
	var accountStatus string
	if err := pool.QueryRow(context.Background(),
		`SELECT account_status FROM users WHERE id = $1`, target.id).Scan(&accountStatus); err != nil {
		t.Fatalf("read account_status: %v", err)
	}
	if accountStatus != "suspended" {
		t.Errorf("account_status = %q, want suspended", accountStatus)
	}
}

// ─── The sender itself ──────────────────────────────────────────────────

// TestMailerUnconfiguredNeverPretends is the H20 degradation rule stated at the
// lowest level: an unconfigured sender must be constructible, callable, and
// incapable of reporting success.
func TestMailerUnconfiguredNeverPretends(t *testing.T) {
	cases := []struct {
		name string
		cfg  auth.MailerConfig
	}{
		{"everything empty", auth.MailerConfig{}},
		{"host only", auth.MailerConfig{Host: "smtp.example.org"}},
		{"no from address", auth.MailerConfig{Host: "smtp.example.org", Port: 587}},
		{"port out of range", auth.MailerConfig{Host: "smtp.example.org", Port: 70000, From: "a@b.co"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := auth.NewMailer(tc.cfg)
			if m != nil {
				t.Fatalf("NewMailer returned a sender for an unusable config %+v", tc.cfg)
			}
			if m.Configured() {
				t.Error("a nil mailer reports itself configured")
			}
			// The point of the whole exercise: calling it is safe and honest.
			if err := m.Send(context.Background(), "a@b.co", "s", "b"); err == nil {
				t.Error("an unconfigured mailer reported a successful send")
			}
		})
	}
}

// TestMailerDeliversUTF8 proves the sender works against a real SMTP
// conversation, and that an Arabic body survives it — the codes this system
// sends travel in Arabic sentences, and a body that arrives as mojibake is a
// code nobody can read.
func TestMailerDeliversUTF8(t *testing.T) {
	stub := newFakeSMTP(t)
	m := auth.NewMailer(auth.MailerConfig{Host: "127.0.0.1", Port: stub.port(), From: "no-reply@test.local"})
	if m == nil {
		t.Fatal("NewMailer returned nil for a usable config")
	}
	const body = "رمز التأكيد: 123456"
	if err := m.Send(context.Background(), "owner@example.org", "تأكيد", body); err != nil {
		t.Fatalf("send: %v", err)
	}
	got := stub.decodedBodies()
	if len(got) != 1 {
		t.Fatalf("delivered %d messages, want 1", len(got))
	}
	if !strings.Contains(got[0], body) {
		t.Errorf("delivered body = %q, want it to contain %q", got[0], body)
	}
}

// TestMailerRefusesHeaderInjection — the recipient and subject are the only
// caller-controlled header values, so a newline in either must be refused
// rather than sanitised.
func TestMailerRefusesHeaderInjection(t *testing.T) {
	stub := newFakeSMTP(t)
	m := auth.NewMailer(auth.MailerConfig{Host: "127.0.0.1", Port: stub.port(), From: "no-reply@test.local"})
	err := m.Send(context.Background(), "owner@example.org",
		"hello\r\nBcc: attacker@example.net", "body")
	if err == nil {
		t.Fatal("a subject carrying a header break was accepted")
	}
	if len(stub.decodedBodies()) != 0 {
		t.Error("an injected message was delivered")
	}
}

// TestMaskEmailKeepsTheAddressUnreadable — the masked form goes into logs and
// onto the screen, so it must not be the address.
func TestMaskEmailKeepsTheAddressUnreadable(t *testing.T) {
	cases := map[string]string{
		"ahmed@example.org": "ah•••@example.org",
		"ab@example.org":    "•••@example.org",
		"notanaddress":      "•••",
	}
	for in, want := range cases {
		if got := auth.MaskEmail(in); got != want {
			t.Errorf("MaskEmail(%q) = %q, want %q", in, got, want)
		}
	}
}
