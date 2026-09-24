// registration_phone_test.go — the registration profile's phone1 / phone2 get
// the same treatment as every other phone the system stores.
//
// Client feedback round 1: SubmitRegistration wrote extras.Phone1 / Phone2
// into user_profiles straight from the request body. auth.NormalizePhone was
// never applied, so "0750 858 2031", "+9647508582031" and "07508582031" —
// the same number — were stored as three different strings, and a number that
// is not a phone number at all was stored happily.
//
// Integration tests against a throwaway Postgres, skipped unless
// TEST_DATABASE_URL is set.
package users

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// newRegistrationUser inserts a bare pre-registration account.
func newRegistrationUser(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	var id int64
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO users (phone, role_id, active, registration_status)
		 VALUES ($1, 1, 1, 'incomplete') RETURNING id`,
		fmt.Sprintf("9647%08d", rand.Intn(100000000)),
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	return id
}

// submittedProfilePhones reads back what actually landed in the profile row.
func submittedProfilePhones(t *testing.T, pool *pgxpool.Pool, userID int64) (string, string) {
	t.Helper()
	var p1, p2 *string
	if err := pool.QueryRow(context.Background(),
		`SELECT phone1, phone2 FROM user_profiles WHERE user_id = $1 ORDER BY id LIMIT 1`,
		userID,
	).Scan(&p1, &p2); err != nil {
		t.Fatalf("read profile phones: %v", err)
	}
	deref := func(p *string) string {
		if p == nil {
			return ""
		}
		return *p
	}
	return deref(p1), deref(p2)
}

// TestSubmitRegistrationNormalizesProfilePhones pins that every spelling of one
// Iraqi number reaches the database in the single canonical form, so a search
// or a duplicate check can ever match.
func TestSubmitRegistrationNormalizesProfilePhones(t *testing.T) {
	pool := newDupTestPool(t)
	store := NewStore(pool)

	for _, spelling := range []string{"0750 858 2031", "07508582031", "7508582031", "+964 750 858 2031", "9647508582031"} {
		userID := newRegistrationUser(t, pool)
		if _, err := store.SubmitRegistration(context.Background(), userID, "Test Person", "", "Erbil", 1,
			RegistrationExtras{Phone1: spelling, Phone2: spelling}); err != nil {
			t.Fatalf("SubmitRegistration(%q): %v", spelling, err)
		}
		p1, p2 := submittedProfilePhones(t, pool, userID)
		if p1 != "9647508582031" || p2 != "9647508582031" {
			t.Errorf("phone %q stored as phone1=%q phone2=%q, want the canonical %q",
				spelling, p1, p2, "9647508582031")
		}
	}
}

// TestSubmitRegistrationRejectsAnUnusableProfilePhone pins that garbage is
// refused rather than silently stored. Each of these is something
// auth.NormalizePhone cannot reduce to a number.
func TestSubmitRegistrationRejectsAnUnusableProfilePhone(t *testing.T) {
	pool := newDupTestPool(t)
	store := NewStore(pool)

	for _, bad := range []string{"123", "not a phone", "+96477380002" /* 9-digit Iraqi NSN, one short */} {
		for field, extras := range map[string]RegistrationExtras{
			"phone1": {Phone1: bad},
			"phone2": {Phone2: bad},
		} {
			userID := newRegistrationUser(t, pool)
			_, err := store.SubmitRegistration(context.Background(), userID, "Test Person", "", "Erbil", 1, extras)
			if !errors.Is(err, ErrInvalidProfilePhone) {
				t.Errorf("%s = %q: err = %v, want ErrInvalidProfilePhone", field, bad, err)
			}
		}
	}
}

// TestSubmitRegistrationAcceptsAbsentProfilePhones — both fields are optional
// (they sit behind the form's per-field rules), so blank must stay blank and
// must not be mistaken for an invalid number.
func TestSubmitRegistrationAcceptsAbsentProfilePhones(t *testing.T) {
	pool := newDupTestPool(t)
	userID := newRegistrationUser(t, pool)

	if _, err := NewStore(pool).SubmitRegistration(context.Background(), userID, "Test Person", "", "Erbil", 1,
		RegistrationExtras{}); err != nil {
		t.Fatalf("SubmitRegistration with no phones: %v", err)
	}
	if p1, p2 := submittedProfilePhones(t, pool, userID); p1 != "" || p2 != "" {
		t.Errorf("absent phones stored as %q / %q, want both empty", p1, p2)
	}
}
