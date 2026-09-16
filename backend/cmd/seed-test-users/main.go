// Command seed-test-users creates the test accounts the chat end-to-end test
// plan needs — docs/testing/chat-e2e-test-plan-2026-09.md, §1.6 — in one go,
// and can remove them again afterwards.
//
// Ten accounts: a Super Admin, an Administrator, a Supervisor, an Employee
// deliberately WITHOUT sensitive_data, two donors, a beneficiary, two
// volunteers and a guest. Every one is built through the same functions the
// running server uses, so it behaves like an account a person made (see
// internal/seedtestusers/seed.go for the list).
//
// It writes data, so nothing happens without -confirm. Without it, the command
// prints the database it would write to and exactly what it would do, and
// exits.
//
// Usage:
//
//	DATABASE_URL=... go run ./cmd/seed-test-users                 # dry run
//	DATABASE_URL=... go run ./cmd/seed-test-users -confirm        # create them
//	DATABASE_URL=... go run ./cmd/seed-test-users -cleanup        # dry run
//	DATABASE_URL=... go run ./cmd/seed-test-users -cleanup -confirm
//	DATABASE_URL=... go run ./cmd/seed-test-users -prefix=qa -confirm
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/seedtestusers"
)

func main() {
	prefix := flag.String("prefix", seedtestusers.DefaultPrefix,
		"prefix for every generated username and display name, so the accounts are obviously test ones")
	confirm := flag.Bool("confirm", false,
		"actually write to the database; without it the command only reports what it would do")
	cleanup := flag.Bool("cleanup", false,
		"remove the accounts this command created for -prefix, instead of creating them")
	flag.Parse()

	// DATABASE_URL is the same env var cmd/server/main.go reads for its
	// Postgres DSN, so this command connects to the same database with the
	// same configuration convention as the server and the other one-off
	// scripts in this directory.
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("seed-test-users: DATABASE_URL is required")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatalf("seed-test-users: connect: %v", err)
	}
	defer pool.Close()

	// The destination is printed BEFORE anything else, every single run,
	// because the difference between a throwaway database and Railway is one
	// shell variable and there is no way to tell them apart afterwards.
	fmt.Printf("Database: %s\n", describeTarget(dsn))
	fmt.Printf("Prefix:   %s   (usernames %s_sa … %s_g)\n",
		seedtestusers.NormalizePrefix(*prefix),
		seedtestusers.NormalizePrefix(*prefix), seedtestusers.NormalizePrefix(*prefix))
	fmt.Printf("Phones:   %s\n\n", seedtestusers.ReservedPhoneBlockLabel)

	if *cleanup {
		runCleanup(ctx, pool, *prefix, *confirm)
		return
	}
	runSeed(ctx, pool, *prefix, *confirm)
}

// runSeed creates the fixture, or describes what it would create.
func runSeed(ctx context.Context, pool *pgxpool.Pool, prefix string, confirm bool) {
	planned := seedtestusers.Plan(prefix)
	if !confirm {
		fmt.Printf("DRY RUN — nothing was written. Add -confirm to create these %d account(s):\n\n", len(planned))
		printTable(planned, false)
		fmt.Println("\nAn account that already exists is reused, not duplicated.")
		return
	}

	res, err := seedtestusers.Seed(ctx, pool, prefix)
	if err != nil {
		log.Fatalf("seed-test-users: %v", err)
	}
	fmt.Printf("Created %d account(s), reused %d that already existed.\n\n", res.Created, res.Reused())
	printTable(res.Accounts, true)
	fmt.Println()
	fmt.Println("All ten passwords are the same, and none of these accounts has sensitive_data:")
	fmt.Printf("  · password: %s\n", seedtestusers.DefaultPassword)
	fmt.Println("  · staff sign in on the dashboard with USERNAME + password; members sign in in the app with PHONE + password.")
	fmt.Println("  · E1 has no sensitive_data grant, on purpose — step 8 of the test plan is about turning it on.")
	fmt.Println("  · if a password was changed by hand after an earlier run, this command does not overwrite it,")
	fmt.Println("    and that row of the table is then wrong. Delete the account with -cleanup and re-seed it.")
	fmt.Printf("\nTo remove them again: -cleanup -confirm -prefix=%s\n", seedtestusers.NormalizePrefix(prefix))
}

// runCleanup removes the fixture, or describes what it would remove.
func runCleanup(ctx context.Context, pool *pgxpool.Pool, prefix string, confirm bool) {
	if !confirm {
		fmt.Println("DRY RUN — nothing was deleted. Add -confirm to delete the accounts below,")
		fmt.Println("and only those: each one must match BOTH its seeded username AND its seeded")
		fmt.Println("phone number inside the reserved block, or it is left alone.")
		fmt.Println()
		printTable(seedtestusers.Plan(prefix), false)
		return
	}

	res, err := seedtestusers.Cleanup(ctx, pool, prefix)
	if err != nil {
		log.Fatalf("seed-test-users: %v", err)
	}
	fmt.Printf("Deleted %d account(s): %s\n", res.Deleted, joinOrNone(res.DeletedKeys))
	if len(res.Missing) > 0 {
		fmt.Printf("Not present (nothing to do): %s\n", strings.Join(res.Missing, ", "))
	}
	for _, r := range res.Refused {
		fmt.Printf("KEPT %s — %s\n", r.Key, r.Reason)
	}
	if len(res.Refused) > 0 {
		fmt.Println("\nEvery account marked KEPT is untouched. Deal with each one on the dashboard and re-run if you want it gone.")
	}
}

// printTable prints the credentials, one row per account. withIDs adds the
// user id, which only exists after the accounts have been written.
func printTable(accounts []seedtestusers.Account, withIDs bool) {
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	header := "NAME\tPHONE\tUSERNAME\tPASSWORD\tROLE\tWHAT IT IS FOR"
	if withIDs {
		header = "NAME\tID\tPHONE\tUSERNAME\tPASSWORD\tROLE\tWHAT IT IS FOR"
	}
	fmt.Fprintln(w, header)
	for _, a := range accounts {
		phone := a.Phone
		if phone == "" {
			phone = "— (guest: no phone)"
		}
		if withIDs {
			fmt.Fprintf(w, "%s\t%d\t%s\t%s\t%s\t%s\t%s\n",
				a.Key, a.UserID, phone, a.Username, a.Password, roleLabel(a), a.Purpose)
			continue
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n",
			a.Key, phone, a.Username, a.Password, roleLabel(a), a.Purpose)
	}
	_ = w.Flush()
}

// roleLabel renders the one column that answers "what kind of account is
// this?" — a staff tier, a member role, or guest.
func roleLabel(a seedtestusers.Account) string {
	switch {
	case a.IsGuest:
		return "guest"
	case a.StaffTier != "":
		return "staff / " + a.StaffTier
	case a.RoleID == 1:
		return "donor (role 1)"
	case a.RoleID == 2:
		return "beneficiary (role 2)"
	case a.RoleID == 3:
		return "volunteer (role 3)"
	default:
		return "no role"
	}
}

// describeTarget renders the DSN's host and database name and NOTHING else.
// The operator has to see which database they are about to write to; they must
// not see the password, which would then be sitting in their terminal history.
func describeTarget(dsn string) string {
	u, err := url.Parse(dsn)
	if err != nil || u.Host == "" {
		return "(could not read DATABASE_URL — host unknown)"
	}
	name := strings.TrimPrefix(u.Path, "/")
	if name == "" {
		name = "(default)"
	}
	return fmt.Sprintf("%s / %s", u.Host, name)
}

// joinOrNone keeps an empty list from printing as a bare, puzzling blank.
func joinOrNone(items []string) string {
	if len(items) == 0 {
		return "none"
	}
	return strings.Join(items, ", ")
}
