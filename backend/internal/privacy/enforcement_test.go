// K8 — the Privacy Settings screen was a row of switches wired to nothing.
//
// THE SHAPE OF THE GAP
// `user_profiles.field_privacy` has stored each user's "don't show these
// fields to other people" list since migration 040, and the catalogue of
// switches has been data-driven since migration 083. But the column had
// exactly three touch points in the entire backend, ALL of them the owner
// reading or writing their OWN row:
//
//	users.go GetFieldPrivacy      — owner reads their list back
//	users.go SetFieldPrivacy      — owner saves their list
//	users.go GetAccountForClient  — the column echoed in the owner's payload
//
// Not one query that serves a profile to SOMEBODY ELSE consulted it. The same
// went for the alias choice (display_name_mode / alias_name, migration 073).
// So a user could switch "الهاتف" off, and their phone number still appeared
// in the other party's chat list.
//
// These tests are the missing half: they exercise the real serving queries —
// the ones the app actually calls — with one user hiding fields and another
// user reading. Every one of them failed before the enforcement landed.
//
// They need a throwaway Postgres and are skipped unless TEST_DATABASE_URL is
// set, so `go test ./...` stays green on a bare checkout:
//
//	createdb godonation_k8          # empty — the harness applies migrations
//	TEST_DATABASE_URL='postgres://localhost:5432/godonation_k8?sslmode=disable' \
//	  go test ./internal/privacy/ -v
package privacy_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/beneficiary"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/db"
	"github.com/karam-flutter/humanitarian-backend/internal/postengagement"
	"github.com/karam-flutter/humanitarian-backend/internal/sponsorships"
)

// ─── Harness ────────────────────────────────────────────────────────────

func newPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set — skipping privacy-enforcement integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatalf("connect test database: %v", err)
	}
	if err := db.RunMigrations(ctx, pool, "../../migrations"); err != nil {
		pool.Close()
		t.Fatalf("run migrations: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seq hands out phone numbers in a reserved range so fixtures can never
// collide with a real account or with each other (users.phone is UNIQUE).
// runTag keeps two runs against the same database apart, so a run that dies
// before its cleanup cannot make the next one fail on a duplicate phone.
var (
	seq    int64
	runTag = time.Now().UnixNano() % 100000
)

// makeUser creates a user + profile and deletes both afterwards. hidden is
// written straight into field_privacy, exactly as SetFieldPrivacy would.
func makeUser(t *testing.T, pool *pgxpool.Pool, name string, hidden []string) (id int64, phone string) {
	t.Helper()
	ctx := context.Background()
	seq++
	phone = fmt.Sprintf("96479%05d%04d", runTag, seq)
	if hidden == nil {
		hidden = []string{} // the column is NOT NULL; nil would be a NULL
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (phone, role_id, active, registration_status)
		 VALUES ($1, 1, 1, 'approved') RETURNING id`, phone,
	).Scan(&id); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO user_profiles (user_id, full_name, gender, address, field_privacy)
		 VALUES ($1, $2, 'Male', 'Erbil', $3)`, id, name, hidden,
	); err != nil {
		t.Fatalf("insert profile: %v", err)
	}
	t.Cleanup(func() {
		bg := context.Background()
		_, _ = pool.Exec(bg, `DELETE FROM user_profiles WHERE user_id = $1`, id)
		_, _ = pool.Exec(bg, `DELETE FROM users WHERE id = $1`, id)
	})
	return id, phone
}

// setAlias records the "show my alias instead of my real name" choice.
func setAlias(t *testing.T, pool *pgxpool.Pool, userID int64, alias string) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`UPDATE user_profiles SET display_name_mode = 'alias', alias_name = $2 WHERE user_id = $1`,
		userID, alias); err != nil {
		t.Fatalf("set alias: %v", err)
	}
}

func deref(p *string) string {
	if p == nil {
		return "<nil>"
	}
	return *p
}

// ─── Donor ↔ campaign-owner chat (GET /api/chats) ───────────────────────

// The row the client can reproduce by hand: switch "الهاتف" off, then have the
// other party open the chat list.
func TestChatThreadListHidesWhatTheOwnerHid(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	hider, hiderPhone := makeUser(t, pool, "Hidden Person", []string{"full_name", "phone"})
	viewer, _ := makeUser(t, pool, "Viewing Person", nil)
	openThread(t, pool, viewer, hider)

	store := chat.New(pool)
	views, err := store.ListThreadsForUser(ctx, viewer)
	if err != nil {
		t.Fatalf("ListThreadsForUser: %v", err)
	}
	v := findThread(t, views, hider)
	if v.OtherName != nil {
		t.Errorf("other_name = %q — the counterpart hid full_name", deref(v.OtherName))
	}
	if v.OtherPhone != nil {
		t.Errorf("other_phone = %q (real number %q) — the counterpart hid phone", deref(v.OtherPhone), hiderPhone)
	}
}

// Hiding is not blanket muting: a field the user left ON must still be served,
// or the fix would be a different bug.
func TestChatThreadListStillShowsWhatTheOwnerLeftVisible(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	hider, hiderPhone := makeUser(t, pool, "Named Person", []string{"phone"}) // name NOT hidden
	viewer, _ := makeUser(t, pool, "Viewing Person", nil)
	openThread(t, pool, viewer, hider)

	views, err := chat.New(pool).ListThreadsForUser(ctx, viewer)
	if err != nil {
		t.Fatalf("ListThreadsForUser: %v", err)
	}
	v := findThread(t, views, hider)
	if v.OtherName == nil || *v.OtherName != "Named Person" {
		t.Errorf("other_name = %q, want %q — only phone was hidden", deref(v.OtherName), "Named Person")
	}
	if v.OtherPhone != nil {
		t.Errorf("other_phone = %q (real %q) — phone was hidden", deref(v.OtherPhone), hiderPhone)
	}
}

// An alias is the stand-in the user picked for exactly this situation, so it
// is shown where the real name would have been.
func TestChatThreadListSubstitutesTheChosenAlias(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	hider, _ := makeUser(t, pool, "Real Name", []string{"full_name"})
	setAlias(t, pool, hider, "أبو محمد")
	viewer, _ := makeUser(t, pool, "Viewing Person", nil)
	openThread(t, pool, viewer, hider)

	views, err := chat.New(pool).ListThreadsForUser(ctx, viewer)
	if err != nil {
		t.Fatalf("ListThreadsForUser: %v", err)
	}
	v := findThread(t, views, hider)
	if v.OtherName == nil || *v.OtherName != "أبو محمد" {
		t.Errorf("other_name = %q, want the chosen alias", deref(v.OtherName))
	}
}

// Nobody is masked from themselves — the owner's own settings must never blank
// out their own data.
func TestOwnerStillSeesTheirOwnDetails(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	hider, hiderPhone := makeUser(t, pool, "Hidden Person", []string{"full_name", "phone"})
	other, _ := makeUser(t, pool, "Other Person", nil)
	openThread(t, pool, other, hider)

	// The hider reads their own chat list: the OTHER party is the one whose
	// settings apply, and that party hid nothing.
	views, err := chat.New(pool).ListThreadsForUser(ctx, hider)
	if err != nil {
		t.Fatalf("ListThreadsForUser: %v", err)
	}
	v := findThread(t, views, other)
	if v.OtherName == nil || *v.OtherName != "Other Person" {
		t.Errorf("other_name = %q, want %q", deref(v.OtherName), "Other Person")
	}

	// And their own name still appears on their own messages.
	msgs, err := chat.New(pool).ListMessagesForViewer(ctx, threadIDBetween(t, pool, other, hider), hider)
	if err != nil {
		t.Fatalf("ListMessagesForViewer: %v", err)
	}
	var sawOwn bool
	for _, m := range msgs {
		if m.SenderUserID == hider {
			sawOwn = true
			if m.SenderName == nil || *m.SenderName != "Hidden Person" {
				t.Errorf("own sender_name = %q, want %q — a user is never hidden from themselves",
					deref(m.SenderName), "Hidden Person")
			}
		}
	}
	if !sawOwn {
		t.Fatalf("fixture problem: the hider sent no message")
	}
	_ = hiderPhone
}

// Message bubbles carry the sender's name too, and that is a second place the
// hidden name leaked.
func TestChatMessagesHideTheSendersName(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	hider, _ := makeUser(t, pool, "Hidden Sender", []string{"full_name"})
	viewer, _ := makeUser(t, pool, "Viewing Person", nil)
	tid := openThread(t, pool, viewer, hider)

	msgs, err := chat.New(pool).ListMessagesForViewer(ctx, tid, viewer)
	if err != nil {
		t.Fatalf("ListMessagesForViewer: %v", err)
	}
	for _, m := range msgs {
		if m.SenderUserID == hider && m.SenderName != nil {
			t.Errorf("sender_name = %q — that sender hid full_name", deref(m.SenderName))
		}
	}

	// The admin view is a DIFFERENT mechanism (the sensitive_data permission),
	// and must keep returning the real name.
	raw, err := chat.New(pool).ListMessages(ctx, tid)
	if err != nil {
		t.Fatalf("ListMessages: %v", err)
	}
	var sawRealName bool
	for _, m := range raw {
		if m.SenderUserID == hider && m.SenderName != nil && *m.SenderName == "Hidden Sender" {
			sawRealName = true
		}
	}
	if !sawRealName {
		t.Errorf("the admin ListMessages lost the real name — staff visibility is governed by sensitive_data, not by this")
	}
}

// ─── Public beneficiary cases (GET /api/beneficiary_cases, no auth) ─────

func TestPublicCaseHidesWhatTheOwnerHid(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	owner, _ := makeUser(t, pool, "Case Owner", []string{"full_name", "phone", "address"})
	caseID := makeCase(t, pool, owner)

	items, err := beneficiary.NewStore(pool).ListPublicCasesForViewer(ctx, "approved", 200, 0)
	if err != nil {
		t.Fatalf("ListPublicCasesForViewer: %v", err)
	}
	c := findCase(t, items, caseID)
	if c.FullName != nil {
		t.Errorf("full_name = %q on an unauthenticated listing — the owner hid it", deref(c.FullName))
	}
	if c.Phone != nil {
		t.Errorf("phone = %q on an unauthenticated listing — the owner hid it", deref(c.Phone))
	}
	if c.Address != nil {
		t.Errorf("address = %q on an unauthenticated listing — the owner hid it", deref(c.Address))
	}
	// Not hidden, so it must survive — the case still has to be usable.
	if c.City == nil || *c.City != "Kirkuk" {
		t.Errorf("city = %q, want Kirkuk — city was not hidden", deref(c.City))
	}
}

func TestPublicCaseOwnerStillSeesTheirOwnCase(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	owner, _ := makeUser(t, pool, "Case Owner", []string{"full_name", "phone"})
	caseID := makeCase(t, pool, owner)

	items, err := beneficiary.NewStore(pool).ListPublicCasesForViewer(ctx, "approved", 200, owner)
	if err != nil {
		t.Fatalf("ListPublicCasesForViewer: %v", err)
	}
	c := findCase(t, items, caseID)
	if c.FullName == nil {
		t.Errorf("the owner cannot see the name on their own case")
	}
}

// TestPublicCaseWithNoOwnerPublishesNoContactDetails is the end-to-end version
// of the ownerless rule, driven through the same store method the HTTP handler
// calls, against a real row.
//
// The per-owner privacy loop can only consult an owner's settings, so a case
// with user_id NULL reaches the response having passed through no consent
// decision at all. viewerID 0 here is the anonymous caller the endpoint's
// optional bearer allows.
func TestPublicCaseWithNoOwnerPublishesNoContactDetails(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	caseID := makeOwnerlessCase(t, pool)

	items, err := beneficiary.NewStore(pool).ListPublicCasesForViewer(ctx, "approved", 200, 0)
	if err != nil {
		t.Fatalf("ListPublicCasesForViewer: %v", err)
	}
	c := findCase(t, items, caseID)

	if c.UserID != nil {
		t.Fatalf("fixture problem: case %d has an owner, so it is not testing the ownerless path", caseID)
	}
	if c.FullName != nil {
		t.Errorf("full_name = %q to an anonymous caller on an OWNERLESS case — no owner exists who could have consented", deref(c.FullName))
	}
	if c.Phone != nil {
		t.Errorf("phone = %q to an anonymous caller on an OWNERLESS case", deref(c.Phone))
	}
	if c.Address != nil {
		t.Errorf("address = %q to an anonymous caller on an OWNERLESS case", deref(c.Address))
	}
	if c.NationalID != nil {
		t.Errorf("national_id = %q — stripped unconditionally since 73a20f3", deref(c.NationalID))
	}
	// The case must remain a usable listing, or the fix has broken the feature
	// it was protecting.
	if c.City == nil || *c.City != "Kirkuk" {
		t.Errorf("city = %q, want Kirkuk — donors pick a case by where it is", deref(c.City))
	}
	if c.PublicTitle != "Ownerless test case" {
		t.Errorf("public_title = %q, want it intact — the card has nothing to show without it", c.PublicTitle)
	}
	if c.CaseCode == "" {
		t.Error("case_code was cleared; it is how a donor refers to the case")
	}
}

// ─── Sponsorships (GET /api/sponsorships) ───────────────────────────────

func TestSponsorshipListHidesDonorIdentity(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	donor, donorPhone := makeUser(t, pool, "Quiet Donor", []string{"full_name", "phone"})
	viewer, _ := makeUser(t, pool, "Someone Else", nil)
	makeSponsorship(t, pool, donor)

	items, err := sponsorships.New(pool).List(ctx, sponsorships.ListFilters{ViewerUserID: viewer, Limit: 200})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	var seen bool
	for _, it := range items {
		if it.DonorUserID == nil || int64(*it.DonorUserID) != donor {
			continue
		}
		seen = true
		if it.DonorFullName != nil {
			t.Errorf("donor_full_name = %q — that donor hid full_name", deref(it.DonorFullName))
		}
		if it.DonorPhone != nil {
			t.Errorf("donor_phone = %q (real %q) — that donor hid phone", deref(it.DonorPhone), donorPhone)
		}
	}
	if !seen {
		t.Fatalf("fixture problem: the donor's sponsorship was not returned")
	}
}

// ─── Media comments (GET /api/media/:id/comments) ───────────────────────

func TestCommentFeedHidesTheCommenterName(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	hider, _ := makeUser(t, pool, "Hidden Commenter", []string{"full_name"})
	viewer, _ := makeUser(t, pool, "Reader", nil)
	postID := makePost(t, pool)
	makeComment(t, pool, postID, hider)

	items, err := postengagement.New(pool).ListCommentsForViewer(ctx, postID, viewer, 50)
	if err != nil {
		t.Fatalf("ListCommentsForViewer: %v", err)
	}
	var seen bool
	for _, c := range items {
		if c.UserID != hider {
			continue
		}
		seen = true
		if c.UserName == "Hidden Commenter" {
			t.Errorf("user_name = %q — that commenter hid full_name", c.UserName)
		}
	}
	if !seen {
		t.Fatalf("fixture problem: the comment was not returned")
	}
}

// ─── Case ↔ volunteer chat (GET /api/case-chats) ────────────────────────

func TestCaseVolunteerChatHidesTheCounterpartName(t *testing.T) {
	pool := newPool(t)
	ctx := context.Background()

	volunteer, _ := makeUser(t, pool, "Hidden Volunteer", []string{"full_name"})
	beneficiaryUser, _ := makeUser(t, pool, "Beneficiary", nil)
	makeCaseVolThread(t, pool, volunteer, beneficiaryUser)

	views, err := casevolchat.New(pool).ListThreadsForUser(ctx, beneficiaryUser)
	if err != nil {
		t.Fatalf("ListThreadsForUser: %v", err)
	}
	var seen bool
	for _, v := range views {
		if v.OtherUserID != volunteer {
			continue
		}
		seen = true
		if v.OtherName != nil {
			t.Errorf("other_name = %q — the volunteer hid full_name", deref(v.OtherName))
		}
	}
	if !seen {
		t.Fatalf("fixture problem: the thread was not returned")
	}
}
