// Package seedtestusers builds the fixed set of test accounts that the chat
// end-to-end test plan (docs/testing/chat-e2e-test-plan-2026-09.md, §1.6) asks
// a tester to have before starting. It is the logic behind
// cmd/seed-test-users; nothing else in the server imports it.
//
// The matrix, the names and the reasons are taken from that document, not
// invented here — if the plan changes, this file changes with it.
//
// Two properties the rest of the package depends on:
//
//   - Every identity is a pure function of the -prefix flag. The same prefix
//     always produces the same usernames, phone numbers and passwords, which is
//     what lets Seed be idempotent and Cleanup be exact rather than a guess.
//   - Every phone number is inside one reserved block that cannot be a real
//     Iraqi mobile, so a run against the live database can never collide with,
//     or delete, somebody's account.
package seedtestusers

import (
	"fmt"
	"strings"
)

// ─── Credentials ────────────────────────────────────────────────────────────

// DefaultPassword is the one password every seeded account gets. It is printed
// in the command's output; it exists to be typed on a phone during testing, and
// is deliberately the same everywhere so a tester switching between nine
// accounts never has to look it up.
//
// Long enough to clear the four-character floor the dashboard's own create-user
// endpoint enforces (internal/handlers/admin_status.go).
const DefaultPassword = "ChatTest2026!"

// ─── The reserved phone block ───────────────────────────────────────────────

// reservedNSN is the first seven digits of every seeded phone number's Iraqi
// national number, to which a three-digit index is appended, giving the
// ten-digit NSN that auth.NormalizePhone requires.
//
// Why this block is safe: an Iraqi MOBILE national number always begins with 7
// (the 075x/077x/078x/079x networks). Nothing assignable begins 1555, and no
// Iraqi landline is ten digits long. So a number in this block cannot be a real
// subscriber's, which is the whole reason the range exists — this command
// writes to a live database and must never be able to touch a real account.
const reservedNSN = "1555000"

// ReservedPhoneBlock is the stored, normalised prefix every seeded phone
// shares — <dial code><NSN prefix>. auth.NormalizePhone reduces every spelling
// of these numbers to this form, which is what users.phone's UNIQUE index is
// over (PR #134 / OPOS #26636).
const ReservedPhoneBlock = "964" + reservedNSN

// ReservedPhoneBlockLabel is how the block is described to the operator in the
// command's output, so they can see at a glance which numbers were used.
const ReservedPhoneBlockLabel = "+964 1 555 000 0xx (reserved test block — not a real Iraqi number)"

// reservedPhoneLen is the length of a stored seeded number: "964" + a ten-digit
// national number.
const reservedPhoneLen = len("964") + 10

// InReservedPhoneBlock reports whether a stored phone number is one this
// package could have written. Cleanup uses it as its second identity check, so
// an account that merely shares a username can never be deleted.
func InReservedPhoneBlock(phone string) bool {
	return len(phone) == reservedPhoneLen && strings.HasPrefix(phone, ReservedPhoneBlock)
}

// ─── The account matrix ─────────────────────────────────────────────────────

// Spec is one account in the test plan's minimum set: what it is, and what it
// is for. RoleID 0 means "no member role" — a staff account or a guest, which
// is exactly how the app stores them (users.role_id is NULL).
type Spec struct {
	// Key is the plan's short name for the account ("D", "E1", "SA"). It is
	// also the tail of the generated username.
	Key string
	// Label is the human description that goes into the display name.
	Label string
	// RoleID is the member role: 1 donor/grantor, 2 beneficiary/eligible
	// recipient, 3 volunteer. 0 for staff and guests.
	RoleID int
	// StaffTier is the dashboard tier ("super_admin", "admin", "supervisor",
	// "employee"), or "" for a non-staff account, in which case the column
	// keeps its 'user' default.
	StaffTier string
	// IsGuest marks the one account created through the guest door: a username
	// and password, no phone number at all.
	IsGuest bool
	// PhoneIndex is this account's slot in the reserved block. Ignored when
	// IsGuest is true. Slots are never reused or renumbered — an account keeps
	// its number for the life of the fixture.
	PhoneIndex int
	// Purpose is the "why it exists" column of the test plan's table, printed
	// in the credentials table so the tester knows what each login is for.
	Purpose string
}

// Specs is the test plan's §1.6 table, in the order the accounts must be
// created: the Super Admin comes first because it is the staff member every
// later registration approval is attributed to.
var Specs = []Spec{
	{
		Key: "SA", Label: "Super Admin", StaffTier: "super_admin", PhoneIndex: 1,
		Purpose: "Creates everything; sees real names; the only account that can grant permissions and delete permanently.",
	},
	{
		Key: "A", Label: "Administrator", StaffTier: "admin", PhoneIndex: 2,
		Purpose: "Admin-level without being the Super Admin — proves Trash restore and the admin defaults.",
	},
	{
		Key: "SUP", Label: "Supervisor", StaffTier: "supervisor", PhoneIndex: 3,
		Purpose: "The middle tier: everything except delete. Step 8 checks SUP is still refused a masked group after E1 is granted.",
	},
	{
		Key: "E1", Label: "Employee", StaffTier: "employee", PhoneIndex: 4,
		Purpose: "Employee WITHOUT sensitive_data — the star of step 8. Must be refused a masked group until you grant it by hand.",
	},
	{
		Key: "D", Label: "Donor", RoleID: 1, PhoneIndex: 5,
		Purpose: "Sends a connect request from a donation; sits in the masked group; requests the marriage meeting in step 5.",
	},
	{
		Key: "D2", Label: "Second donor", RoleID: 1, PhoneIndex: 6,
		Purpose: "Someone D is NOT in a group with — step 1c's \"a member cannot open a group they are not in\".",
	},
	{
		Key: "B", Label: "Beneficiary", RoleID: 2, PhoneIndex: 7,
		Purpose: "Sends a connect request from a case; sits opposite D in the masked group; owns the marriage profile.",
	},
	{
		Key: "V1", Label: "Volunteer", RoleID: 3, PhoneIndex: 8,
		Purpose: "Member of the team group (step 4).",
	},
	{
		Key: "V2", Label: "Volunteer", RoleID: 3, PhoneIndex: 9,
		Purpose: "The other half of the team group — two are needed to prove they see each other's real names.",
	},
	{
		Key: "G", Label: "Guest", IsGuest: true,
		Purpose: "Step 9: no chats, no chat notifications, no pushes, support screen reads only. Signs in with username + password.",
	},
}

// ─── Identities ─────────────────────────────────────────────────────────────

// Account is one planned or seeded account: the Spec plus the identity derived
// from the prefix, plus — after Seed — the row it ended up as.
type Account struct {
	Spec
	// Username is the sign-in name. Staff need it for the dashboard login and
	// the guest needs it for the app; the others get one too because it is the
	// half of Cleanup's identity check that a phone number cannot provide.
	Username string
	// FullName is what staff see in the dashboard. It carries the prefix so a
	// test account is obvious in a list of real ones.
	FullName string
	// Phone is the stored, normalised number — empty for the guest.
	Phone string
	// Password is the plaintext to type. Always DefaultPassword; carried per
	// account so the printed table needs no special case.
	Password string
	// UserID is the users.id row, set by Seed. Zero in a plan.
	UserID int64
	// Created is true when Seed inserted this account rather than finding it.
	Created bool
}

// Plan returns the full set of identities for a prefix without touching the
// database. Seed and Cleanup both start here, which is why they agree about
// what "this command's accounts" means.
func Plan(prefix string) []Account {
	prefix = NormalizePrefix(prefix)
	out := make([]Account, 0, len(Specs))
	for _, spec := range Specs {
		acct := Account{
			Spec:     spec,
			Username: fmt.Sprintf("%s_%s", prefix, strings.ToLower(spec.Key)),
			FullName: fmt.Sprintf("%s %s %s", prefix, spec.Key, spec.Label),
			Password: DefaultPassword,
		}
		if !spec.IsGuest {
			acct.Phone = fmt.Sprintf("%s%s%03d", "964", reservedNSN, spec.PhoneIndex)
		}
		out = append(out, acct)
	}
	return out
}

// NormalizePrefix folds the -prefix flag to the one spelling the usernames are
// built from. Usernames are stored folded elsewhere in the server
// (normalizeUsername in internal/handlers), and a case-only difference between
// two runs would make Cleanup miss what Seed wrote.
func NormalizePrefix(prefix string) string {
	prefix = strings.ToLower(strings.TrimSpace(prefix))
	if prefix == "" {
		return DefaultPrefix
	}
	return prefix
}

// DefaultPrefix is the -prefix flag's default: short, lowercase, and obviously
// not a real person's name.
const DefaultPrefix = "test"
