// mailer.go — the standard-library SMTP sender (H20).
//
// # WHY THIS FILE EXISTS
//
// The client asked for a change to the main-admin account to be confirmed by a
// code delivered "through BOTH phone and email". The phone half has existed
// since Phase 19 (otpiq.go). The email half did not exist ANYWHERE in this
// system: no SMTP client, no mail provider, no dependency in go.mod. Nothing in
// the backend had ever sent an email.
//
// # WHY net/smtp AND NOT A LIBRARY
//
// The whole of what this system sends by email is a six-digit code and one line
// of text. `net/smtp` is in the standard library, needs no new module, and is
// stable. Every dependency is a liability; this one buys nothing.
//
// # THE RULE THIS FILE EXISTS TO ENFORCE
//
// SMTP_* is EMPTY in every environment the team can reach. An unconfigured
// sender therefore has to be the normal case, not the error case, and it must:
//
//	NEVER crash        — NewMailer returns nil, exactly like NewOTPIQClient.
//	NEVER block        — every dial, handshake and write is under a deadline.
//	NEVER lie          — Send returns ErrMailNotConfigured. There is no code
//	                     path in this file that reports success for a message
//	                     that did not leave the process.
//
// Callers decide what "no email channel" means for them; this file only makes
// sure they are told the truth. See internal/handlers/admin_main_admin_guard.go
// for H20's answer (it refuses the change) and admin_permissions.go for H1's
// (it proceeds and says loudly that the factor is degraded).
//
// # WHAT IS NEVER LOGGED
//
// The password, the code, and the message body. Failures are logged by the
// CALLER with the recipient masked; this file returns errors and prints
// nothing, so there is no path by which a credential reaches a log line.
package auth

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"mime"
	"net"
	"net/mail"
	"net/smtp"
	"strconv"
	"strings"
	"time"
)

// mailDialTimeout bounds the whole conversation — dial, TLS handshake, AUTH,
// DATA and QUIT. A relay that stops answering must not hold an HTTP handler
// open; 10s matches the OTPIQ client's budget for the same reason.
const mailDialTimeout = 10 * time.Second

// Errors callers distinguish. ErrMailNotConfigured is the one that matters:
// it is the difference between "we tried and it failed" and "there is no email
// channel at all", and the two lead to different words on the operator's screen.
var (
	ErrMailNotConfigured = errors.New("email delivery is not configured (SMTP_HOST/SMTP_PORT/SMTP_FROM)")
	ErrMailBadRecipient  = errors.New("the recipient address is not a valid email address")
	ErrMailHeaderInject  = errors.New("the subject or recipient contains a line break")
	ErrMailInsecure      = errors.New("the relay offered no TLS and credentials are configured")
)

// MailerConfig is the sender's five settings. It mirrors config.SMTPConfig
// field for field; main.go maps one to the other explicitly so that
// internal/auth keeps reading no configuration of its own — the same shape
// every other client in this package has.
type MailerConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

// Mailer sends one short plaintext message over SMTP. Zero value is unusable —
// call NewMailer.
type Mailer struct {
	cfg MailerConfig
}

// NewMailer returns a ready sender, or nil when the configuration is
// insufficient to send anything.
//
// Returning nil rather than an error is deliberate and copies NewOTPIQClient:
// "no channel configured" is the ordinary state of this system, so it must be
// representable without every caller handling an error at construction time. A
// nil *Mailer is safe to call — Send answers ErrMailNotConfigured — so callers
// need one check, at the point where it matters, not two.
func NewMailer(cfg MailerConfig) *Mailer {
	cfg.Host = strings.TrimSpace(cfg.Host)
	cfg.From = strings.TrimSpace(cfg.From)
	if cfg.Host == "" || cfg.From == "" || cfg.Port <= 0 || cfg.Port > 65535 {
		return nil
	}
	return &Mailer{cfg: cfg}
}

// Configured reports whether this sender can attempt a delivery. Nil-safe, so
// a caller holding a possibly-nil *Mailer can ask before composing anything.
func (m *Mailer) Configured() bool { return m != nil }

// From returns the configured sender address (for operator-facing diagnostics).
// Nil-safe and never exposes any other setting — in particular not the password.
func (m *Mailer) From() string {
	if m == nil {
		return ""
	}
	return m.cfg.From
}

// Send delivers one UTF-8 plaintext message to a single recipient.
//
// Returns nil ONLY when the relay accepted the message (SMTP QUIT after a
// successful DATA). Every other outcome is an error, including the
// unconfigured case — nothing here treats "we did not send" as success.
//
// ctx bounds the dial; the connection additionally carries an absolute deadline
// so a relay that accepts the TCP connection and then goes quiet cannot hold
// the caller open past mailDialTimeout.
func (m *Mailer) Send(ctx context.Context, to, subject, body string) error {
	if m == nil {
		return ErrMailNotConfigured
	}
	to = strings.TrimSpace(to)
	if _, err := mail.ParseAddress(to); err != nil {
		return fmt.Errorf("%w: %v", ErrMailBadRecipient, err)
	}
	// Header injection: a newline in either field would let a caller append
	// arbitrary headers (Bcc:, Content-Type:) to the message. Both are refused
	// rather than sanitised — silently rewriting a caller's input is how the
	// next injection gets missed.
	if strings.ContainsAny(to, "\r\n") || strings.ContainsAny(subject, "\r\n") {
		return ErrMailHeaderInject
	}

	addr := net.JoinHostPort(m.cfg.Host, strconv.Itoa(m.cfg.Port))
	dialer := &net.Dialer{Timeout: mailDialTimeout}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return fmt.Errorf("dial smtp %s: %w", addr, err)
	}
	// One deadline for the whole conversation. Set on the raw connection so it
	// survives the TLS upgrade below.
	_ = conn.SetDeadline(time.Now().Add(mailDialTimeout))

	tlsCfg := &tls.Config{ServerName: m.cfg.Host, MinVersion: tls.VersionTLS12}
	// Port 465 speaks TLS from the first byte (SMTPS); 587 and 25 negotiate it
	// with STARTTLS after EHLO. Choosing on the port is what every mail client
	// does and is what the operator will expect from the number they typed.
	if m.cfg.Port == 465 {
		conn = tls.Client(conn, tlsCfg)
	}

	client, err := smtp.NewClient(conn, m.cfg.Host)
	if err != nil {
		_ = conn.Close()
		return fmt.Errorf("smtp greeting from %s: %w", m.cfg.Host, err)
	}
	defer func() { _ = client.Close() }()

	if m.cfg.Port != 465 {
		if ok, _ := client.Extension("STARTTLS"); ok {
			if err := client.StartTLS(tlsCfg); err != nil {
				return fmt.Errorf("starttls to %s: %w", m.cfg.Host, err)
			}
		} else if m.cfg.Username != "" || m.cfg.Password != "" {
			// Refusing beats downgrading: a password offered to a plaintext
			// relay is a password published, and the operator gets a clear
			// error instead of a silent leak.
			return ErrMailInsecure
		}
	}

	if m.cfg.Username != "" || m.cfg.Password != "" {
		if err := client.Auth(smtp.PlainAuth("", m.cfg.Username, m.cfg.Password, m.cfg.Host)); err != nil {
			// The error text comes from the relay and can echo the username;
			// it never contains the password, and this function logs nothing.
			return fmt.Errorf("smtp auth as %s: %w", m.cfg.Username, err)
		}
	}

	if err := client.Mail(m.cfg.From); err != nil {
		return fmt.Errorf("smtp MAIL FROM %s: %w", m.cfg.From, err)
	}
	if err := client.Rcpt(to); err != nil {
		return fmt.Errorf("smtp RCPT TO: %w", err)
	}
	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("smtp DATA: %w", err)
	}
	if _, err := w.Write([]byte(buildMessage(m.cfg.From, to, subject, body))); err != nil {
		_ = w.Close()
		return fmt.Errorf("smtp write body: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("smtp close body: %w", err)
	}
	// Quit is what turns "the relay read our bytes" into "the relay accepted
	// the message", so its error is returned rather than deferred away.
	if err := client.Quit(); err != nil {
		return fmt.Errorf("smtp QUIT: %w", err)
	}
	return nil
}

// buildMessage renders an RFC 5322 message.
//
// The subject is RFC 2047 Q-encoded and the body is base64'd UTF-8 because
// every message this system sends is written in Arabic. Sending those bytes
// raw would arrive as mojibake on any relay that is not 8BITMIME-clean, which
// is precisely the sort of failure nobody notices until a code is unreadable.
func buildMessage(from, to, subject, body string) string {
	var b strings.Builder
	b.WriteString("From: " + from + "\r\n")
	b.WriteString("To: " + to + "\r\n")
	b.WriteString("Subject: " + mime.QEncoding.Encode("utf-8", subject) + "\r\n")
	b.WriteString("Date: " + time.Now().UTC().Format(time.RFC1123Z) + "\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	b.WriteString("Content-Transfer-Encoding: base64\r\n")
	b.WriteString("\r\n")
	enc := base64.StdEncoding.EncodeToString([]byte(body))
	// 76-character lines, as SMTP requires for base64 bodies.
	for len(enc) > 76 {
		b.WriteString(enc[:76] + "\r\n")
		enc = enc[76:]
	}
	b.WriteString(enc + "\r\n")
	return b.String()
}

// MaskEmail hides the local part of an address for display and logs
// ("ah•••@example.org"), so an operator can recognise their own address
// without the full one appearing on a screen or in a log file.
//
// Lives here rather than beside maskPhone in the handlers package because the
// mailer is what knows an address is an address, and both packages need it.
func MaskEmail(addr string) string {
	addr = strings.TrimSpace(addr)
	at := strings.LastIndex(addr, "@")
	if at <= 0 {
		return "•••"
	}
	local, domain := addr[:at], addr[at:]
	if len(local) <= 2 {
		return "•••" + domain
	}
	return local[:2] + "•••" + domain
}
