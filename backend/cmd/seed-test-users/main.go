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
// The same run also seeds what step 5 of the plan needs and nothing in the
// database otherwise has: two marriage profiles owned by fixture accounts, and
// one PENDING meeting request from D about B's profile, waiting for staff to
// approve it on the dashboard (see internal/seedtestusers/marriage.go).
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
		fmt.Printf("\nIt would also create the marriage fixtures step 5 of the test plan needs: %d marriage\n",
			len(seedtestusers.MarriageProfileSpecs))
		fmt.Printf("profile(s) owned by the fixture accounts, and one PENDING meeting request from %s about\n",
			seedtestusers.MarriageRequesterKey)
		fmt.Printf("%s's profile, for staff to approve on the dashboard's Marriage → Marriage Requests page.\n",
			seedtestusers.MarriageRequestAboutKey)
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
	printMarriageSummary(res.Marriage)
	fmt.Printf("\nTo remove them again: -cleanup -confirm -prefix=%s\n", seedtestusers.NormalizePrefix(prefix))
}

// runCleanup removes the fixture, or describes what it would remove.
func runCleanup(ctx context.Context, pool *pgxpool.Pool, prefix string, confirm bool) {
	if !confirm {
		fmt.Println("DRY RUN — nothing was deleted. Add -confirm to delete the accounts below,")
		fmt.Println("and only those: each one must match BOTH its seeded username AND its seeded")
		fmt.Println("phone number inside the reserved block, or it is left alone.")
		fmt.Println("The marriage profiles and meeting requests seeded for those accounts go with them;")
		fmt.Println("a marriage profile created by hand on a test account is NOT touched.")
		fmt.Println()
		printTable(seedtestusers.Plan(prefix), false)
		return
	}

	res, err := seedtestusers.Cleanup(ctx, pool, prefix)
	if err != nil {
		log.Fatalf("seed-test-users: %v", err)
	}
	fmt.Printf("Deleted %d account(s): %s\n", res.Deleted, joinOrNone(res.DeletedKeys))
	// The marriage rows go with the accounts and are counted separately,
	// because nobody asked for them by name and they are easy to miss.
	if res.MarriageProfilesDeleted > 0 || res.MarriageRequestsDeleted > 0 {
		fmt.Printf("Also removed %d seeded marriage profile(s) and %d meeting request(s), with the chats they opened.\n",
			res.MarriageProfilesDeleted, res.MarriageRequestsDeleted)
	}
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

// printMarriageSummary explains, in plain language, the marriage fixtures the
// run created and what the client is meant to do with them next.
//
// This is the part of the output somebody acts on rather than reads, so it
// names the screen, the row and the button, not the tables.
func printMarriageSummary(m *seedtestusers.MarriageResult) {
	if m == nil {
		return
	}
	fmt.Println("\nMARRIAGE — the fixtures for step 5 of the test plan (the meeting request and the chat it opens):")
	for _, p := range m.Profiles {
		state := "already existed"
		if p.Created {
			state = "created now"
		}
		fmt.Printf("  · profile %s — owned by %s, %s, %s (%s). Visible in the app's marriage search.\n",
			p.ProfileCode, p.OwnerKey, p.Gender, p.City, state)
	}
	state := "was already waiting"
	if m.RequestCreated {
		state = "created now"
	}
	fmt.Printf("  · %s has asked for a meeting about %s's profile %s — the request %s and is PENDING.\n",
		m.RequesterKey, m.AboutOwnerKey, m.AboutProfileCode, state)
	fmt.Println("\nWHAT TO DO NEXT, on the dashboard:")
	fmt.Println("  1. Sign in as SA (or any staff account with the Marriage module).")
	fmt.Println("  2. Open the sidebar group \"Marriage\" → \"Marriage Requests\" (page /marriage-requests,")
	fmt.Println("     «طلبات الزواج»).")
	fmt.Printf("  3. Find the row FROM the %s account, ABOUT PROFILE %s, with the status \"Pending\",\n",
		m.RequesterKey, m.AboutProfileCode)
	fmt.Println("     and click \"Approve\". That opens the staff-mediated chat and sends the profile")
	fmt.Printf("     owner (%s) an invite to accept in the app.\n", m.AboutOwnerKey)
	fmt.Println("  4. Sign in to the app as that owner to Accept or Decline the invite (step 5a / 5b).")
	fmt.Println("\n  Approving needs nothing else filled in by hand: the request carries a message, and the")
	fmt.Println("  approving staff member is taken from the dashboard session.")
	fmt.Println("  Re-running this command after you approve opens a FRESH pending request, so step 5 can")
	fmt.Println("  be repeated; a request still waiting for a decision is reused, never duplicated.")
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
