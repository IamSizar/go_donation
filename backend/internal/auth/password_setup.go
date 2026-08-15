// password_setup.go — the single-use ticket that carries "this phone answered a
// code" from /auth/otp/verify to /auth/password/set, and the password rules
// both the app and the server agree on.
//
// # WHY A TICKET EXISTS AT ALL
//
// Under the owner's design an OTP proves a number ONCE, at account creation,
// and a password is what signs a user in afterwards. That means the verify step
// and the set-a-password step are two requests, and something has to carry the
// proof between them. A16 (389fbe4) recorded that nothing could: "a verified
// code leaves no durable trace (the record is deleted on success), so this
// handler could not have checked one even if it had wanted to." This file is
// that trace.
//
// The ticket is deliberately NOT a session token:
//
//   - it is minted by /auth/otp/verify, which no longer issues sessions;
//   - the ONLY thing it authorises is giving a password to an account that has
//     none (see handlers/auth_password_setup.go), so it can never open an
//     account, never reset a password, and never be replayed for access;
//   - it is single-use, expires in ten minutes, is bound to the phone it was
//     issued for, and survives at most five wrong guesses.
//
// # WHY SHA-256 HERE AND BCRYPT EVERYWHERE ELSE
//
// bcrypt is a deliberate slowdown for LOW-entropy secrets a human chose — a
// password, or a six-digit code. A ticket is 256 bits from crypto/rand, so
// there is nothing to slow down: guessing it is infeasible whatever the hash
// costs, and a plain SHA-256 with a constant-time compare is the right and
// boring primitive. Passwords in this package stay on bcrypt, as they must.
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
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// SetupTicketTTL is how long a verified number stays claimable. Long enough
	// to type a password twice on a slow phone, short enough that an abandoned
	// signup does not leave a usable claim lying around.
	SetupTicketTTL = 10 * time.Minute

	// SetupTicketMaxAttempts caps wrong tickets against one phone, mirroring
	// OTPMaxAttempts so the two halves of the flow behave the same way.
	SetupTicketMaxAttempts = 5

	// SetupTicketBytes is the entropy in a ticket: 32 bytes, hex-encoded to 64
	// characters.
	SetupTicketBytes = 32

	// MinPasswordLength is the server-side floor for a NEW account password,
	// counted in characters rather than bytes so an Arabic or Kurdish password
	// is measured the same way an English one is.
	//
	// Eight, not the six the guest browsing account uses (handlers.GuestRegister),
	// because these two passwords do not protect the same thing: a guest row can
	// browse, while this password is the ONLY door to a real account holding a
	// person's registration, wallet and — for five accounts — the dashboard. The
	// guest rule is left alone; changing it is not this change's business.
	MinPasswordLength = 8

	// MaxPasswordBytes is bcrypt's own hard limit. golang.org/x/crypto/bcrypt
	// returns ErrPasswordTooLong above 72 bytes, so a longer password would
	// become a 500 instead of a validation message. Note this counts BYTES:
	// 72 bytes is only 36 Arabic characters, which is still a generous
	// passphrase and is the library's ceiling, not ours.
	MaxPasswordBytes = 72
)

// ErrPasswordTooShort / ErrPasswordTooLong are returned by ValidateNewPassword
// so callers can map each to its own translatable `code` without re-deriving
// the rule.
var (
	ErrPasswordTooShort = errors.New("password is shorter than the minimum")
	ErrPasswordTooLong  = errors.New("password is longer than bcrypt accepts")
)

// NormalizeNewPassword trims the surrounding whitespace from a submitted
// password and returns the value that must be hashed.
//
// It trims because the VERIFIER trims: handlers.Login compares
// strings.TrimSpace(req.Password) against the stored hash. A password stored
// with a trailing space could therefore never be used to sign in again — the
// account would look set and behave locked. Trimming on the way in is what
// makes set → sign-in round-trip.
func NormalizeNewPassword(raw string) string {
	return strings.TrimSpace(raw)
}

// ValidateNewPassword applies the server-side password rules to an ALREADY
// normalized value (see NormalizeNewPassword). The client mirrors these rules
// for instant feedback; this is the one that decides.
//
// Length only, on purpose. Composition rules ("one capital, one symbol") push
// people toward shorter, more predictable passwords and are no longer
// recommended by NIST SP 800-63B; length is the rule that earns its keep.
func ValidateNewPassword(password string) error {
	if utf8.RuneCountInString(password) < MinPasswordLength {
		return ErrPasswordTooShort
	}
	if len(password) > MaxPasswordBytes {
		return ErrPasswordTooLong
	}
	return nil
}

// SetupTicketResult says why a ticket was or was not accepted. Every non-OK
// value is a refusal; the caller maps it to a translatable code.
type SetupTicketResult int

const (
	SetupTicketOK        SetupTicketResult = iota // accepted and consumed
	SetupTicketMissing                            // no ticket outstanding for this phone
	SetupTicketExpired                            // issued, but the ten minutes ran out
	SetupTicketExhausted                          // too many wrong guesses
	SetupTicketMismatch                           // wrong ticket value
)

// SetupTicketStore is the password_setup_tickets table (migration 102).
// One row per phone: requesting a new one replaces the old, so a user who
// restarts the flow never has two live claims.
type SetupTicketStore struct {
	Pool *pgxpool.Pool
}

func NewSetupTicketStore(pool *pgxpool.Pool) *SetupTicketStore {
	return &SetupTicketStore{Pool: pool}
}

// hashSetupTicket is the stored form of a ticket. See the file header for why
// this is SHA-256 rather than bcrypt.
func hashSetupTicket(ticket string) string {
	sum := sha256.Sum256([]byte(ticket))
	return hex.EncodeToString(sum[:])
}

// GenerateSetupTicket returns a fresh 256-bit ticket in hex. It can never be
// mistaken for an OTP code — ValidateCodeFormat requires exactly six digits and
// this is 64 hex characters — which is what keeps the two credentials from
// being submitted to each other's endpoints by accident.
func GenerateSetupTicket() (string, error) {
	buf := make([]byte, SetupTicketBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generate setup ticket: %w", err)
	}
	return hex.EncodeToString(buf), nil
}

// Issue mints a ticket for phone and stores its hash, replacing any previous
// one. The plaintext is returned to the caller and never stored or logged.
func (s *SetupTicketStore) Issue(ctx context.Context, phone string) (string, error) {
	ticket, err := GenerateSetupTicket()
	if err != nil {
		return "", err
	}
	now := time.Now().UTC()
	_, err = s.Pool.Exec(ctx,
		`INSERT INTO password_setup_tickets (phone, ticket_hash, attempts, created_at, expires_at)
		 VALUES ($1, $2, 0, $3, $4)
		 ON CONFLICT (phone) DO UPDATE
		   SET ticket_hash = EXCLUDED.ticket_hash,
		       attempts    = 0,
		       created_at  = EXCLUDED.created_at,
		       expires_at  = EXCLUDED.expires_at`,
		phone, hashSetupTicket(ticket), now, now.Add(SetupTicketTTL))
	if err != nil {
		return "", fmt.Errorf("store setup ticket: %w", err)
	}
	return ticket, nil
}

// Consume checks a submitted ticket against the row held for phone and, on a
// match, deletes it so it cannot be spent twice. attemptsLeft is meaningful
// only for SetupTicketMismatch.
//
// A non-nil error means we could not tell — the caller must fail CLOSED and
// must NOT set a password.
func (s *SetupTicketStore) Consume(ctx context.Context, phone, ticket string) (SetupTicketResult, int, error) {
	var (
		storedHash string
		attempts   int
		expiresAt  time.Time
	)
	err := s.Pool.QueryRow(ctx,
		`SELECT ticket_hash, attempts, expires_at FROM password_setup_tickets WHERE phone = $1`,
		phone).Scan(&storedHash, &attempts, &expiresAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return SetupTicketMissing, 0, nil
		}
		return SetupTicketMissing, 0, fmt.Errorf("load setup ticket: %w", err)
	}

	if time.Now().After(expiresAt) {
		_ = s.Clear(ctx, phone)
		return SetupTicketExpired, 0, nil
	}
	if attempts >= SetupTicketMaxAttempts {
		_ = s.Clear(ctx, phone)
		return SetupTicketExhausted, 0, nil
	}
	if subtle.ConstantTimeCompare([]byte(storedHash), []byte(hashSetupTicket(ticket))) != 1 {
		left := SetupTicketMaxAttempts - (attempts + 1)
		if left < 0 {
			left = 0
		}
		if _, incErr := s.Pool.Exec(ctx,
			`UPDATE password_setup_tickets SET attempts = attempts + 1 WHERE phone = $1`,
			phone); incErr != nil {
			// The guess counter is the only thing bounding a brute force, so a
			// failed increment is reported rather than swallowed; the caller
			// fails closed on it.
			return SetupTicketMismatch, left, fmt.Errorf("count setup ticket attempt: %w", incErr)
		}
		return SetupTicketMismatch, left, nil
	}

	if err := s.Clear(ctx, phone); err != nil {
		// Refusing here is the safe side: a ticket we could not delete is a
		// ticket that could be spent again.
		return SetupTicketMissing, 0, fmt.Errorf("consume setup ticket: %w", err)
	}
	return SetupTicketOK, 0, nil
}

// Clear removes any outstanding ticket for phone.
func (s *SetupTicketStore) Clear(ctx context.Context, phone string) error {
	_, err := s.Pool.Exec(ctx, `DELETE FROM password_setup_tickets WHERE phone = $1`, phone)
	return err
}
