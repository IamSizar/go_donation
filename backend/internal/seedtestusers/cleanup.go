// cleanup.go — removing the fixture, and nothing else.
//
// The rule this file exists to enforce: Cleanup deletes an account only when
// it can prove that account is one Seed wrote. "Starts with the prefix" is not
// that proof — a real person can be called anything — so every candidate has
// to match the WHOLE identity Plan would have given it:
//
//	a member or staff account : username exactly, AND the exact phone number,
//	                            AND that number inside the reserved block
//	the guest                 : username exactly, AND is_guest, AND no phone
//
// Anything else is reported and left alone. There is no flag to override this.
package seedtestusers

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Refusal is one account Cleanup declined to delete, and why. The reason is
// written for the operator reading the command's output, not for a log.
type Refusal struct {
	Key    string
	Reason string
}

// CleanupResult is what one Cleanup run did.
type CleanupResult struct {
	// Deleted counts the accounts removed.
	Deleted int
	// DeletedKeys names them, in Specs order.
	DeletedKeys []string
	// Missing names the fixture accounts that were not in the database — the
	// normal state of a second run, not a problem.
	Missing []string
	// Refused names the accounts that exist under a fixture username but did
	// not prove they were ours, plus any the database would not let go.
	Refused []Refusal
	// MarriageProfilesDeleted / MarriageRequestsDeleted count the marriage
	// fixture rows removed along with the accounts (see marriage.go). They are
	// reported separately because they are rows the operator never asked for
	// by name and would otherwise not know had gone.
	MarriageProfilesDeleted int64
	MarriageRequestsDeleted int64
}

// Cleanup removes the accounts this command created for a prefix.
//
// Deleting a user row takes its profile, its device tokens, its per-user
// permission rows and all of its chat threads and messages with it — those
// foreign keys are ON DELETE CASCADE. Several others are ON DELETE RESTRICT on
// purpose (donations, sponsorships, marketplace orders, a marriage profile:
// the money and the paperwork outlive the account). So an account that donated
// during testing will refuse to delete, and is reported rather than forced:
// tearing out that audit trail is not this command's decision to make.
func Cleanup(ctx context.Context, pool *pgxpool.Pool, prefix string) (*CleanupResult, error) {
	if pool == nil {
		return nil, errors.New("seedtestusers: nil pool")
	}
	res := &CleanupResult{}
	// The stamp the seeded marriage profiles carry, so this run removes only
	// the ones Seed wrote for THIS prefix.
	marriageNote := marriageFixtureNote(prefix)
	for _, acct := range Plan(prefix) {
		id, ok, reason, err := identify(ctx, pool, acct)
		if err != nil {
			return nil, fmt.Errorf("checking %s: %w", acct.Key, err)
		}
		if id == 0 {
			res.Missing = append(res.Missing, acct.Key)
			continue
		}
		if !ok {
			res.Refused = append(res.Refused, Refusal{Key: acct.Key, Reason: reason})
			continue
		}
		if acct.StaffTier == "super_admin" {
			last, err := isLastSuperAdmin(ctx, pool, id)
			if err != nil {
				return nil, fmt.Errorf("checking %s: %w", acct.Key, err)
			}
			if last {
				res.Refused = append(res.Refused, Refusal{
					Key:    acct.Key,
					Reason: "it is the only Super Admin left in this database; deleting it would lock everyone out of the dashboard",
				})
				continue
			}
		}
		// The marriage fixtures go first: marriage_profiles.user_id is
		// ON DELETE RESTRICT, so a surviving profile makes the DELETE below
		// fail outright (see cleanupMarriageRows).
		profiles, requests, err := cleanupMarriageRows(ctx, pool, id, marriageNote)
		res.MarriageProfilesDeleted += profiles
		res.MarriageRequestsDeleted += requests
		if err != nil {
			res.Refused = append(res.Refused, Refusal{
				Key:    acct.Key,
				Reason: fmt.Sprintf("its marriage fixtures could not be removed, so the account was left in place: %v", err),
			})
			continue
		}

		if _, err := pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, id); err != nil {
			// Almost always an ON DELETE RESTRICT foreign key: the account has
			// real records attached. The operator needs the database's own
			// words here, because they name the table.
			res.Refused = append(res.Refused, Refusal{
				Key:    acct.Key,
				Reason: fmt.Sprintf("the database refused to delete user %d: %v", id, err),
			})
			continue
		}
		res.Deleted++
		res.DeletedKeys = append(res.DeletedKeys, acct.Key)
	}
	return res, nil
}

// identify looks up the row behind a fixture username and decides whether it
// is really ours. It returns (0, ...) when no such row exists.
func identify(ctx context.Context, pool *pgxpool.Pool, acct Account) (id int64, ours bool, reason string, err error) {
	var (
		phone   *string
		isGuest bool
	)
	// LOWER() on both sides for the same reason users.GetByUsername does it:
	// rows predating the folding rule are not covered by the partial unique
	// index, which is over the raw column.
	err = pool.QueryRow(ctx,
		`SELECT id, phone, is_guest FROM users WHERE LOWER(username) = LOWER($1) ORDER BY id LIMIT 1`,
		acct.Username,
	).Scan(&id, &phone, &isGuest)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, false, "", nil
	}
	if err != nil {
		return 0, false, "", err
	}

	if acct.IsGuest {
		if !isGuest {
			return id, false, fmt.Sprintf("user %d holds this username but is not a guest account", id), nil
		}
		if phone != nil && *phone != "" {
			return id, false, fmt.Sprintf("user %d holds this username but has a phone number, so it is not the seeded guest", id), nil
		}
		return id, true, "", nil
	}

	if phone == nil || *phone == "" {
		return id, false, fmt.Sprintf("user %d holds this username but has no phone number", id), nil
	}
	if *phone != acct.Phone {
		return id, false, fmt.Sprintf("user %d holds this username but its phone number is not the seeded one", id), nil
	}
	if !InReservedPhoneBlock(*phone) {
		return id, false, fmt.Sprintf("user %d's phone number is outside the reserved test block", id), nil
	}
	return id, true, "", nil
}

// isLastSuperAdmin reports whether this account is the only super_admin in the
// database — the same protection the staff-tier endpoint applies to a demotion
// (internal/handlers/admin_status.go), which a DELETE would otherwise walk
// straight past.
func isLastSuperAdmin(ctx context.Context, pool *pgxpool.Pool, id int64) (bool, error) {
	var others int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM users WHERE staff_tier = 'super_admin' AND id <> $1`, id,
	).Scan(&others); err != nil {
		return false, err
	}
	return others == 0, nil
}
