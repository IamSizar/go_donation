// seed.go — creating the fixture.
//
// Everything here goes through the functions the running server uses, so a
// seeded account behaves like one a person made:
//
//	auth.NormalizePhone            the one spelling users.phone stores (PR #134)
//	bcrypt.GenerateFromPassword    the same hash both login doors compare against
//	users.Store.InsertWithPhone    find-or-create by phone, role NULL, 'incomplete'
//	users.Store.SubmitRegistration name + address + role, moves to 'pending'
//	users.Store.ApproveRegistration the staff approval, attributed to SA
//	users.Store.EnsureGrantorCode / EnsureVolunteerCode  the GR-/VL- identity codes
//	                               (the ER- code is minted inside SubmitRegistration)
//	users.Store.InsertGuest        the "continue as guest" door
//	users.Store.UpsertProfile      the profile writer, with its own audit rows
//
// The three writes that have no function to call — the username, the staff
// tier, and the 'approved' status on a role-less staff account — are done here
// with the same SQL the dashboard handler uses, and each says so at the call
// site. They exist only inside internal/handlers, on the far side of an HTTP
// request this command has no way to make.
package seedtestusers

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/users"
)

// auditSource labels the user_profiles audit rows this command writes, so a
// name that appeared without a person behind it can be traced back here.
const auditSource = "seed-test-users"

// Result is what one Seed run did.
type Result struct {
	// Accounts is every account in the fixture, in Specs order, each carrying
	// the row it now occupies.
	Accounts []Account
	// Created counts the accounts this run inserted; the rest already existed
	// and were brought back to the expected state.
	Created int
}

// Reused counts the accounts that were already there.
func (r *Result) Reused() int { return len(r.Accounts) - r.Created }

// Seed creates (or repairs) the whole account matrix and returns it.
//
// Running it twice is safe and is the expected thing to do: every step is
// either find-or-create or a write that sets a column to a known value, so a
// second run inserts nothing and only puts back anything testing knocked out
// of place — an account suspended mid-test, or a sensitive_data grant left on
// E1 from a previous pass through step 8.
//
// It never overwrites a password that is already set: users.SetPasswordIfUnset
// refuses to, by design. The returned Account still reports DefaultPassword,
// so if somebody has changed one by hand, that one line of the printed table
// will be wrong — which is why the command's output says so.
func Seed(ctx context.Context, pool *pgxpool.Pool, prefix string) (*Result, error) {
	if pool == nil {
		return nil, errors.New("seedtestusers: nil pool")
	}
	store := users.NewStore(pool)
	accounts := Plan(prefix)

	hash, err := bcrypt.GenerateFromPassword([]byte(DefaultPassword), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash the fixture password: %w", err)
	}
	passwordHash := string(hash)

	res := &Result{Accounts: make([]Account, 0, len(accounts))}
	// The first staff account created becomes the approver of every member
	// registration below, because users.registration_reviewed_by is a foreign
	// key into users and a registration approved by nobody reads as one that
	// was never reviewed. Specs puts SA first for exactly this reason.
	var approverID int64

	for _, acct := range accounts {
		seeded, err := seedOne(ctx, pool, store, acct, passwordHash, approverID)
		if err != nil {
			return nil, fmt.Errorf("seeding %s: %w", acct.Key, err)
		}
		if approverID == 0 && seeded.StaffTier != "" {
			approverID = seeded.UserID
		}
		if seeded.Created {
			res.Created++
		}
		res.Accounts = append(res.Accounts, seeded)
	}
	return res, nil
}

// seedOne brings one account to its expected state and returns it with its
// row id filled in.
func seedOne(
	ctx context.Context,
	pool *pgxpool.Pool,
	store *users.Store,
	acct Account,
	passwordHash string,
	approverID int64,
) (Account, error) {
	var err error
	if acct.IsGuest {
		acct, err = ensureGuestRow(ctx, store, acct, passwordHash)
	} else {
		acct, err = ensurePhoneRow(ctx, store, acct)
	}
	if err != nil {
		return acct, err
	}

	// The password comes second so a row that existed without one — the state
	// 36 of 46 production accounts are in (see internal/handlers/auth.go) —
	// gains the fixture password and becomes usable.
	if _, err := store.SetPasswordIfUnset(ctx, acct.UserID, passwordHash); err != nil {
		return acct, fmt.Errorf("set password: %w", err)
	}
	if err := ensureUsername(ctx, pool, acct.UserID, acct.Username); err != nil {
		return acct, err
	}

	if acct.RoleID > 0 {
		if err := ensureMemberRegistration(ctx, store, acct, approverID); err != nil {
			return acct, err
		}
	} else if !acct.IsGuest {
		// A staff account has no member role, so it never passes through the
		// registration form. The dashboard's own create-user endpoint inserts
		// such rows straight at 'approved'
		// (internal/handlers/admin_status.go CreateUser); this is that same
		// value, written to a row that already exists.
		if _, err := pool.Exec(ctx,
			`UPDATE users SET registration_status = 'approved'
			  WHERE id = $1 AND registration_status <> 'approved'`, acct.UserID,
		); err != nil {
			return acct, fmt.Errorf("approve staff account: %w", err)
		}
	}

	// Members got their profile from SubmitRegistration. Staff and the guest
	// need one written explicitly, or they show up nameless everywhere staff
	// read a name.
	if acct.RoleID == 0 {
		name, address := acct.FullName, seedAddress
		if _, err := store.UpsertProfile(ctx, acct.UserID,
			users.ProfileUpdate{FullName: &name, Address: &address},
			auditSource, approverID, map[string]any{"fixture": "seed-test-users"},
		); err != nil {
			return acct, fmt.Errorf("write profile: %w", err)
		}
	}

	if acct.StaffTier != "" {
		if err := ensureStaffTier(ctx, pool, acct.UserID, acct.StaffTier); err != nil {
			return acct, err
		}
	}
	if err := ensureActive(ctx, pool, acct.UserID); err != nil {
		return acct, err
	}
	if err := resetPermissionOverrides(ctx, pool, acct.UserID); err != nil {
		return acct, err
	}
	return acct, nil
}

// seedAddress fills the NOT NULL address column with something that reads as a
// fixture rather than as a real place.
const seedAddress = "Test address (seed-test-users)"

// ensurePhoneRow finds or creates the account behind this fixture's phone
// number, and refuses outright if the number does not normalise into the
// reserved block — the guard that keeps this command away from real accounts.
func ensurePhoneRow(ctx context.Context, store *users.Store, acct Account) (Account, error) {
	// Round-trip through the server's own normaliser rather than trusting the
	// string Plan built: users.phone stores what this function returns, and the
	// UNIQUE index that makes this command idempotent is over that value.
	phone := auth.NormalizePhone(acct.Phone)
	if phone == "" || phone != acct.Phone {
		return acct, fmt.Errorf("phone %q does not normalise to itself (got %q) — the reserved block is wrong",
			acct.Phone, phone)
	}
	if !InReservedPhoneBlock(phone) {
		return acct, fmt.Errorf("phone %q is outside the reserved block %s", phone, ReservedPhoneBlock)
	}

	existing, err := store.GetIDByPhone(ctx, phone)
	if err != nil {
		return acct, fmt.Errorf("look up phone: %w", err)
	}
	id, err := store.InsertWithPhone(ctx, phone)
	if err != nil {
		return acct, fmt.Errorf("insert user: %w", err)
	}
	acct.UserID = id
	acct.Created = existing == 0
	return acct, nil
}

// ensureGuestRow finds or creates the one account with no phone number.
//
// users.InsertGuest refuses a username that is already taken, which is what
// makes the lookup-first order necessary here rather than optional.
func ensureGuestRow(ctx context.Context, store *users.Store, acct Account, passwordHash string) (Account, error) {
	id, _, _, isGuest, err := store.GetByUsername(ctx, acct.Username)
	if err != nil {
		return acct, fmt.Errorf("look up guest username: %w", err)
	}
	if id > 0 {
		if !isGuest {
			// Somebody else owns this name. Creating a second one is
			// impossible and taking this one over would be exactly the
			// "touching an account we did not create" this command forbids.
			return acct, fmt.Errorf("username %q already belongs to a non-guest account (user %d); choose another -prefix",
				acct.Username, id)
		}
		acct.UserID = id
		return acct, nil
	}
	id, err = store.InsertGuest(ctx, acct.Username, passwordHash, acct.FullName)
	if err != nil {
		return acct, fmt.Errorf("insert guest: %w", err)
	}
	acct.UserID = id
	acct.Created = true
	return acct, nil
}

// ensureMemberRegistration puts a member account through the registration form
// and the staff approval, exactly as the app and the dashboard do.
func ensureMemberRegistration(ctx context.Context, store *users.Store, acct Account, approverID int64) error {
	status, err := store.SubmitRegistration(ctx, acct.UserID,
		acct.FullName, "", seedAddress, acct.RoleID, users.RegistrationExtras{})
	if err != nil {
		return fmt.Errorf("submit registration: %w", err)
	}
	// SubmitRegistration preserves an existing approval and otherwise leaves
	// the account 'pending', so this runs on a first pass and is skipped on
	// every later one.
	if status != "approved" {
		if _, err := store.ApproveRegistration(ctx, acct.UserID, approverID); err != nil {
			return fmt.Errorf("approve registration: %w", err)
		}
	}
	// The identity codes the registration handler assigns after submitting
	// (internal/handlers/registration.go). Each is assign-once; re-running
	// changes nothing. Role 2's ER- code is minted inside SubmitRegistration.
	switch acct.RoleID {
	case 1:
		if err := store.EnsureGrantorCode(ctx, acct.UserID); err != nil {
			return fmt.Errorf("assign grantor code: %w", err)
		}
	case 3:
		if err := store.EnsureVolunteerCode(ctx, acct.UserID); err != nil {
			return fmt.Errorf("assign volunteer code: %w", err)
		}
	}
	return nil
}

// ensureUsername writes the sign-in name onto an account that has none.
//
// It is the column the dashboard login looks the account up by
// (users.GetByUsername), and it is half of Cleanup's identity check. An
// existing different name is left alone: overwriting one would be editing an
// account whose history this command does not know.
func ensureUsername(ctx context.Context, pool *pgxpool.Pool, userID int64, username string) error {
	if _, err := pool.Exec(ctx,
		`UPDATE users SET username = $2
		  WHERE id = $1 AND (username IS NULL OR username = '')`,
		userID, username,
	); err != nil {
		return fmt.Errorf("set username %q: %w", username, err)
	}
	return nil
}

// ensureStaffTier promotes the account to its dashboard tier — the same single
// UPDATE the Super-Admin-only staff_tier endpoint performs
// (internal/handlers/admin_status.go, UserStaffTier).
//
// That endpoint's two guards do not apply here: this never demotes anybody (it
// only ever raises a fixture account off the default 'user'), so it cannot
// remove the last super_admin, and there is no session to force-log-out.
func ensureStaffTier(ctx context.Context, pool *pgxpool.Pool, userID int64, tier string) error {
	if _, err := pool.Exec(ctx,
		`UPDATE users SET staff_tier = $2 WHERE id = $1 AND staff_tier <> $2`, userID, tier,
	); err != nil {
		return fmt.Errorf("set staff tier %q: %w", tier, err)
	}
	return nil
}

// ensureActive undoes a suspension or a deactivation from an earlier test run.
// auth.ResolveToken treats 'suspended' and 'banned' as no session at all
// (migration 018), so an account left in either state cannot sign in the next
// morning and the tester has no idea why.
func ensureActive(ctx context.Context, pool *pgxpool.Pool, userID int64) error {
	if _, err := pool.Exec(ctx,
		`UPDATE users SET account_status = 'active', active = 1
		  WHERE id = $1 AND (account_status <> 'active' OR active IS DISTINCT FROM 1)`,
		userID,
	); err != nil {
		return fmt.Errorf("reactivate account: %w", err)
	}
	return nil
}

// resetPermissionOverrides removes every per-user permission row for a seeded
// account, leaving it on its tier's defaults.
//
// This is the requirement "grant each staff account the defaults its tier
// already gets", read literally and correctly: the defaults are in code
// (internal/permissions.moduleDefaultAllowed) and apply when NO row exists.
// Writing rows that merely repeat them would pin the account against the tier
// matrix, so that a later change on the Permissions page silently skipped these
// accounts.
//
// It is also what keeps E1 honest. Step 8 of the test plan grants E1
// sensitive_data and watches the screen change; a second run of the plan needs
// that grant gone again, and this is the reset the ↺ button on the Permissions
// page performs, applied to every box at once (there is no
// permissions.Store function for "all boxes" — ClearUserOverride takes one
// module and action, and the set of boxes is not enumerable from here).
func resetPermissionOverrides(ctx context.Context, pool *pgxpool.Pool, userID int64) error {
	if _, err := pool.Exec(ctx,
		`DELETE FROM role_permissions WHERE user_id = $1`, userID,
	); err != nil {
		return fmt.Errorf("clear per-user permission overrides: %w", err)
	}
	return nil
}
