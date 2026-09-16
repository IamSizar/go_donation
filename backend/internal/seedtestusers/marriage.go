// marriage.go — the marriage fixtures step 5 of the test plan needs.
//
// Step 5 (docs/testing/chat-e2e-test-plan-2026-09.md) is the only surviving
// way to produce a chat invite, and it starts from a marriage profile and a
// meeting request. A database with neither has nothing for staff to approve,
// which is exactly the state the client was left in after seeding only
// accounts. So the same run now also leaves behind:
//
//	two marriage profiles   owned by fixture accounts, in the state the app's
//	                        own search serves (see marriageSearchableSQL)
//	one meeting request     from D about B's profile, status 'pending' — the
//	                        row the dashboard lists with an Approve button
//
// Everything here follows the rules the rest of this package follows: it is
// idempotent, it writes nothing a Cleanup for the same prefix cannot remove,
// and it goes through the real store functions (marriage.Store.Insert,
// marriage.Store.RequestMeeting) wherever they exist. The one exception is
// the profile's staff-set STATUS, which lives behind an HTTP handler — it is
// written here with the same SQL that handler runs, and says so at the call
// site.
package seedtestusers

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/marriage"
)

// ─── What gets seeded ───────────────────────────────────────────────────────

// MarriageProfileSpec is one fixture profile: whose account owns it, and the
// obviously-fake contents it is filled with.
//
// The values are plain and plausible rather than funny: staff read them on the
// dashboard next to real people's profiles, and a joke there is indistinguishable
// from corrupted data. What marks them as fixtures is the private_notes stamp
// (marriageFixtureNote) and the owner's own test account.
type MarriageProfileSpec struct {
	// OwnerKey is the fixture account that owns the profile, by Spec.Key.
	OwnerKey string
	// Gender is capitalised on purpose: the app's search screen offers exactly
	// 'Male' and 'Female'
	// (humanitarian/lib/modules/marriage/screens/marriage_search_screen.dart)
	// and marriage.Store.List matches the column exactly, so a lowercase value
	// would be invisible to the one filter the tester is going to use.
	Gender           string
	Age              int
	City             string
	SocialSummary    string
	MaritalStatus    string // one of marriage.MaritalStatuses
	Religion         string // free text, by design (migration 067)
	EmploymentStatus string // one of marriage.EmploymentStatuses
	WeightKg         int
	HeightCm         int
}

// MarriageProfileSpecs is the pair of profiles every run creates. Two rather
// than one so the app's search shows a list rather than a single card, and so
// the tester can see the gender filter actually filter.
var MarriageProfileSpecs = []MarriageProfileSpec{
	{
		OwnerKey: "B", Gender: "Female", Age: 27, City: "Baghdad",
		SocialSummary:    "Test profile for the marriage flow — not a real person.",
		MaritalStatus:    "single",
		Religion:         "Muslim",
		EmploymentStatus: "employed",
		WeightKg:         60, HeightCm: 165,
	},
	{
		OwnerKey: "D2", Gender: "Male", Age: 31, City: "Erbil",
		SocialSummary:    "Second test profile for the marriage flow — not a real person.",
		MaritalStatus:    "single",
		Religion:         "Muslim",
		EmploymentStatus: "self_employed",
		WeightKg:         78, HeightCm: 178,
	},
}

// MarriageRequesterKey is the fixture account that asks for the meeting: D,
// whose Spec purpose already says it "requests the marriage meeting in step 5".
const MarriageRequesterKey = "D"

// MarriageRequestAboutKey is the profile owner being asked about: B, whose
// Spec purpose already says it "owns the marriage profile".
//
// It must not be the requester — marriagechat.ApproveMeetingRequest refuses
// "requester cannot be the profile owner" — which is why these are two
// different accounts and not one.
const MarriageRequestAboutKey = "B"

// marriageRequestMessage is the note attached to the meeting request. It shows
// in the dashboard's Message column, so it says what the row is for.
const marriageRequestMessage = "Seeded test request — approve me to open the staff-mediated chat."

// marriageRequestType is one of the three kinds the app offers
// (marriage.RequestType): an in-person meeting, which is what the single
// original button meant and what step 5 describes.
const marriageRequestType = "meeting"

// marriageFixtureNote is the stamp every seeded profile carries in
// private_notes — a staff-only column (it is never served to members). It is
// what Cleanup matches on, so a profile somebody created BY HAND on a fixture
// account during testing is never deleted by this command; that one is
// reported instead, through the existing ON DELETE RESTRICT refusal.
func marriageFixtureNote(prefix string) string {
	return fmt.Sprintf("Seeded by seed-test-users (prefix %s) — fixture data, not a real person.",
		NormalizePrefix(prefix))
}

// ─── The result ─────────────────────────────────────────────────────────────

// MarriageProfile is one seeded profile as it ended up in the database.
type MarriageProfile struct {
	OwnerKey    string
	OwnerUserID int64
	ProfileID   int64
	ProfileCode string
	Gender      string
	City        string
	// Created is true when this run inserted the profile rather than finding it.
	Created bool
}

// MarriageResult is the marriage half of one Seed run: what exists now, and
// who is waiting on whom.
type MarriageResult struct {
	Profiles []MarriageProfile
	// RequesterKey / RequesterUserID — the account that asked for the meeting.
	RequesterKey    string
	RequesterUserID int64
	// AboutProfileID / AboutProfileCode / AboutOwnerKey — the profile it asked
	// about. The CODE is what the dashboard shows in its "About profile"
	// column, so it is how the tester finds the right row.
	AboutProfileID   int64
	AboutProfileCode string
	AboutOwnerKey    string
	// RequestID is the marriage_meeting_requests row, and RequestCreated says
	// whether this run opened it or found one still pending.
	RequestID      int64
	RequestCreated bool
}

// ─── Seeding ────────────────────────────────────────────────────────────────

// seedMarriage creates (or repairs) the marriage fixtures for a set of already
// seeded accounts.
//
// Idempotency works the same way as it does for the accounts: a profile is
// found by (owner, fixture stamp) before it is inserted, and a meeting request
// is reused whenever one is still PENDING. A request the client has already
// approved or declined is NOT reused — a decided request gives step 5 nothing
// to approve — so a later run opens a fresh one, which is the same "ask again"
// path the app offers and which marriagechat.ApproveMeetingRequest is built to
// handle (it reuses the existing thread).
func seedMarriage(ctx context.Context, pool *pgxpool.Pool, prefix string, accounts []Account) (*MarriageResult, error) {
	byKey := make(map[string]Account, len(accounts))
	for _, a := range accounts {
		byKey[a.Key] = a
	}
	store := marriage.New(pool)
	note := marriageFixtureNote(prefix)

	res := &MarriageResult{
		RequesterKey:  MarriageRequesterKey,
		AboutOwnerKey: MarriageRequestAboutKey,
	}
	for _, spec := range MarriageProfileSpecs {
		owner, ok := byKey[spec.OwnerKey]
		if !ok || owner.UserID <= 0 {
			return nil, fmt.Errorf("profile owner %q is not in the seeded accounts", spec.OwnerKey)
		}
		profile, err := ensureMarriageProfile(ctx, pool, store, spec, owner, note)
		if err != nil {
			return nil, fmt.Errorf("marriage profile for %s: %w", spec.OwnerKey, err)
		}
		res.Profiles = append(res.Profiles, profile)
		if spec.OwnerKey == MarriageRequestAboutKey {
			res.AboutProfileID = profile.ProfileID
			res.AboutProfileCode = profile.ProfileCode
		}
	}
	if res.AboutProfileID == 0 {
		return nil, fmt.Errorf("no seeded profile is owned by %q, so there is nothing to request a meeting about",
			MarriageRequestAboutKey)
	}

	requester, ok := byKey[MarriageRequesterKey]
	if !ok || requester.UserID <= 0 {
		return nil, fmt.Errorf("the requester account %q is not in the seeded accounts", MarriageRequesterKey)
	}
	res.RequesterUserID = requester.UserID

	id, created, err := ensureMeetingRequest(ctx, pool, store, requester.UserID, res.AboutProfileID)
	if err != nil {
		return nil, fmt.Errorf("meeting request from %s: %w", MarriageRequesterKey, err)
	}
	res.RequestID, res.RequestCreated = id, created
	return res, nil
}

// ensureMarriageProfile finds this owner's fixture profile or creates it, then
// puts it back into the state the app's search and the dashboard expect.
func ensureMarriageProfile(
	ctx context.Context,
	pool *pgxpool.Pool,
	store *marriage.Store,
	spec MarriageProfileSpec,
	owner Account,
	note string,
) (MarriageProfile, error) {
	out := MarriageProfile{
		OwnerKey: spec.OwnerKey, OwnerUserID: owner.UserID,
		Gender: spec.Gender, City: spec.City,
	}

	// The lookup is by owner AND the fixture stamp, never by owner alone: a
	// profile the client filled in by hand on a test account is somebody's
	// work, and this command neither edits nor deletes it.
	err := pool.QueryRow(ctx,
		`SELECT id, profile_code FROM marriage_profiles
		  WHERE user_id = $1 AND private_notes = $2
		  ORDER BY id LIMIT 1`,
		owner.UserID, note,
	).Scan(&out.ProfileID, &out.ProfileCode)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return out, fmt.Errorf("look up existing profile: %w", err)
	}

	if errors.Is(err, pgx.ErrNoRows) {
		gender, city, summary, notes := spec.Gender, spec.City, spec.SocialSummary, note
		maritalStatus, religion, employment := spec.MaritalStatus, spec.Religion, spec.EmploymentStatus
		age, weight, height := spec.Age, spec.WeightKg, spec.HeightCm
		// The real create path: the same function POST /api/marriage runs
		// (internal/handlers/extras.go, MarriageHandler.Post). It mints the
		// profile_code and picks the entry subscription tier itself, which is
		// why neither is invented here — "" means "whatever a real
		// registration would get".
		id, code, err := store.Insert(ctx, owner.UserID,
			&gender, &age, &city, &summary, &notes,
			&maritalStatus, &religion, &employment, &weight, &height,
			"", "employee_only", nil)
		if err != nil {
			return out, fmt.Errorf("insert profile: %w", err)
		}
		out.ProfileID, out.ProfileCode, out.Created = id, code, true
	}

	if err := ensureMarriageProfileSearchable(ctx, pool, out.ProfileID); err != nil {
		return out, err
	}
	return out, nil
}

// ensureMarriageProfileSearchable puts a profile into the state that makes it
// visible to a member searching in the app, and undoes anything an earlier
// test run did to it.
//
// marriage.Store.List serves a profile only when its status is one of
// active/under_review/submitted, its visibility_level is not 'private', and
// owner_deleted_at is NULL. 'active' is chosen over the 'submitted' default
// because it is the approved state a tester would otherwise have to click
// through on the dashboard before step 5 can start.
//
// This is SQL rather than a store call on purpose: the staff status change
// lives inside an HTTP handler (AdminStatusHandler.Marriage, POST
// /api/admin/marriage/:id/status) with no function this command can call, and
// that handler clears owner_deleted_at on every status change — which is
// exactly what is repeated here, including the paused_from_status reset that
// makes a resumed profile stop pointing back at a stale status (migration 110).
func ensureMarriageProfileSearchable(ctx context.Context, pool *pgxpool.Pool, profileID int64) error {
	if _, err := pool.Exec(ctx,
		`UPDATE marriage_profiles
		    SET status = 'active',
		        visibility_level = 'employee_only',
		        owner_deleted_at = NULL,
		        paused_from_status = NULL
		  WHERE id = $1
		    AND (status <> 'active' OR visibility_level = 'private'
		         OR owner_deleted_at IS NOT NULL OR paused_from_status IS NOT NULL)`,
		profileID,
	); err != nil {
		return fmt.Errorf("make profile %d searchable: %w", profileID, err)
	}
	return nil
}

// ensureMeetingRequest returns the pending request from this user about this
// profile, opening one if there is none.
func ensureMeetingRequest(
	ctx context.Context,
	pool *pgxpool.Pool,
	store *marriage.Store,
	fromUserID, profileID int64,
) (id int64, created bool, err error) {
	err = pool.QueryRow(ctx,
		`SELECT id FROM marriage_meeting_requests
		  WHERE from_user_id = $1 AND profile_id = $2 AND status = 'pending'
		  ORDER BY id DESC LIMIT 1`,
		fromUserID, profileID,
	).Scan(&id)
	if err == nil {
		return id, false, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return 0, false, fmt.Errorf("look up pending request: %w", err)
	}
	// The real path again: what POST /api/marriage/:id/request-meeting calls
	// (internal/handlers/extras.go, MarriageHandler.RequestMeeting).
	id, err = store.RequestMeeting(ctx, fromUserID, profileID, marriageRequestMessage, marriageRequestType)
	if err != nil {
		return 0, false, fmt.Errorf("insert request: %w", err)
	}
	return id, true, nil
}

// ─── Cleanup ────────────────────────────────────────────────────────────────

// cleanupMarriageRows removes the marriage rows this command wrote for one
// already-identified fixture account, and returns how many of each went.
//
// It runs immediately before the account itself is deleted, and it has to:
// marriage_profiles.user_id is ON DELETE RESTRICT (migration 002), so a
// surviving profile does not merely linger — it makes the account undeletable.
//
// What it removes, and nothing else:
//
//   - every meeting request this account SENT (they carry no foreign key at
//     all — migration 046 — so nothing would ever clean them up otherwise);
//   - every meeting request ABOUT one of this account's fixture profiles, for
//     the same reason;
//   - this account's fixture profiles, matched by the private_notes stamp.
//
// The chat threads and messages that an approved request opened go with them:
// marriage_chat_threads cascades from both the profile and the request
// (migration 058), and its messages and read marks cascade from the thread.
func cleanupMarriageRows(ctx context.Context, pool *pgxpool.Pool, userID int64, note string) (profiles, requests int64, err error) {
	tag, err := pool.Exec(ctx,
		`DELETE FROM marriage_meeting_requests
		  WHERE from_user_id = $1
		     OR profile_id IN (SELECT id FROM marriage_profiles
		                        WHERE user_id = $1 AND private_notes = $2)`,
		userID, note)
	if err != nil {
		return 0, 0, fmt.Errorf("delete meeting requests for user %d: %w", userID, err)
	}
	requests = tag.RowsAffected()

	tag, err = pool.Exec(ctx,
		`DELETE FROM marriage_profiles WHERE user_id = $1 AND private_notes = $2`,
		userID, note)
	if err != nil {
		return 0, requests, fmt.Errorf("delete marriage profiles for user %d: %w", userID, err)
	}
	profiles = tag.RowsAffected()

	// marriage_saved has no foreign keys either (migration 046): a bookmark
	// pointing at a profile that is gone is an orphan row the app would render
	// as a blank card. Only rows belonging to THIS account are removed —
	// somebody else's bookmark of a fixture profile is not ours to delete, and
	// it disappears from their list on its own, because the profile it names is
	// no longer there to join to.
	if _, err := pool.Exec(ctx, `DELETE FROM marriage_saved WHERE user_id = $1`, userID); err != nil {
		return profiles, requests, fmt.Errorf("delete saved profiles for user %d: %w", userID, err)
	}
	return profiles, requests, nil
}
