// Package deleteguard answers one question for the admin delete routes: if
// this row were deleted right now, what would be destroyed that nobody can put
// back?
//
// WHY IT EXISTS. handlers.trashRow is this repo's recoverable delete: it
// snapshots the row it deletes into trash_items and then runs a real
// `DELETE FROM`. Its own comment records the limit — "FK cascades still fire
// for child rows; those children are not individually trashed". So every
// ON DELETE CASCADE child of a trashed row is destroyed outright and is not in
// the snapshot, and المهملات hands the operator back the parent alone. That is
// worse than a delete with no Trash entry, because the operator has been told
// the action is undoable.
//
// K14 (internal/marriage/owner.go) refused to route marriage_profiles through
// trashRow for exactly this reason and stamped a soft-delete instead; ee50aae
// refused the volunteer-signup delete outright while a conversation existed.
// This package is the shared repository layer behind the second remedy, so the
// handlers stay thin and the counting SQL is in one auditable place.
//
// THE RULE EVERY COUNT IN THIS FILE FOLLOWS. Count evidence that something
// would ACTUALLY BE LOST, never the mere existence of a child row. ee50aae
// counted MESSAGES and not THREADS because a thread is opened automatically on
// approval, so refusing on thread existence would have made nearly every
// approved signup permanently undeletable — a bigger regression than the bug.
// The same discipline is applied here to every parent: rows a user authored,
// money that moved, and evidence that was uploaded are counted; rows the system
// creates for itself, and rows it can regenerate from the parent, are not.
package deleteguard

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is a stateless wrapper over the connection pool, mirroring every other
// repository in internal/.
type Store struct{ Pool *pgxpool.Pool }

// New builds a Store over the given pool.
func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// ─── users ──────────────────────────────────────────────────────────────

// UserRecords is what DELETE /api/admin/users/:id would destroy.
//
// Messages is every chat message that would go, across all four chat systems —
// both the ones this account sent and the ones other people sent in threads
// this account is a party to, because deleting the account cascades the whole
// thread and takes the other side's half of the conversation with it.
//
// WalletTransactions is the account's money ledger: top-ups, donations,
// purchases and refunds. SubscriptionPurchases is the record that the person
// PAID for an engagement subscription — the two categories K14 singled out as
// unacceptable to lose.
//
// NOT counted, deliberately: user_profiles, notification_preferences,
// role_permissions, app_notification_* and the other rows the system creates
// for an account as a matter of course. They exist for practically every
// account, they are rebuilt on next use, and refusing on them would make every
// account permanently undeletable.
type UserRecords struct {
	Messages              int `json:"messages"`
	WalletTransactions    int `json:"wallet_transactions"`
	SubscriptionPurchases int `json:"subscription_purchases"`
}

// Any reports whether anything irreplaceable would be lost.
func (r UserRecords) Any() bool {
	return r.Messages > 0 || r.WalletTransactions > 0 || r.SubscriptionPurchases > 0
}

// ForUser counts what deleting one account would destroy.
//
// The four chat blocks are separate systems with separate tables (donor↔owner,
// engagement, staff↔staff, case↔volunteer) and each has its own set of
// participant columns that cascade, so each is counted on its own terms rather
// than through any shared abstraction — there isn't one.
func (s *Store) ForUser(ctx context.Context, userID int64) (UserRecords, error) {
	var r UserRecords
	if userID <= 0 {
		return r, errors.New("userID is required")
	}
	err := s.Pool.QueryRow(ctx, `
		SELECT
		  -- Donor ↔ campaign-owner chat: the thread dies if this account is
		  -- either party or opened it, so every message in it dies too.
		  (SELECT COUNT(*) FROM chat_messages m
		     JOIN chat_threads t ON t.id = m.thread_id
		    WHERE m.sender_user_id = $1
		       OR t.donor_user_id  = $1
		       OR t.owner_user_id  = $1
		       OR t.initiated_by   = $1)
		+ (SELECT COUNT(*) FROM marriage_chat_messages m
		     JOIN marriage_chat_threads t ON t.id = m.thread_id
		    WHERE m.sender_user_id    = $1
		       OR t.owner_user_id     = $1
		       OR t.requester_user_id = $1)
		+ (SELECT COUNT(*) FROM staff_chat_messages m
		     JOIN staff_chat_threads t ON t.id = m.thread_id
		    WHERE m.sender_user_id = $1
		       OR t.user_a_id      = $1
		       OR t.user_b_id      = $1)
		  -- Case ↔ volunteer chat has a fourth door: the thread also hangs off
		  -- the signup, and the signup hangs off this account.
		+ (SELECT COUNT(*) FROM case_volunteer_chat_messages m
		     JOIN case_volunteer_chat_threads t ON t.id = m.thread_id
		    WHERE m.sender_user_id      = $1
		       OR t.volunteer_user_id   = $1
		       OR t.beneficiary_user_id = $1
		       OR t.signup_id IN (SELECT s.id FROM volunteer_mission_signups s
		                           WHERE s.user_id = $1))                       AS messages,
		  (SELECT COUNT(*) FROM wallet_transactions WHERE user_id = $1)         AS wallet_transactions,
		  (SELECT COUNT(*) FROM marriage_subscription_purchases
		    WHERE user_id = $1)                                                 AS subscription_purchases`,
		userID,
	).Scan(&r.Messages, &r.WalletTransactions, &r.SubscriptionPurchases)
	if err != nil {
		return r, fmt.Errorf("count records for user %d: %w", userID, err)
	}
	return r, nil
}

// ─── marriage_profiles (the ADMIN route) ────────────────────────────────

// MarriageProfileRecords is what DELETE /api/admin/marriage/:id would destroy.
//
// This is the cascade K14 already refused to let the OWNER's own delete touch
// (internal/marriage/owner.go stamps owner_deleted_at instead, and says so at
// length). The same profile row is reachable from the staff dashboard, where
// it still went through trashRow — so the documented hazard was live on the
// staff side. These are the two children it names.
type MarriageProfileRecords struct {
	Messages              int `json:"messages"`
	SubscriptionPurchases int `json:"subscription_purchases"`
}

// Any reports whether anything irreplaceable would be lost.
func (r MarriageProfileRecords) Any() bool {
	return r.Messages > 0 || r.SubscriptionPurchases > 0
}

// ForMarriageProfile counts what deleting one engagement profile would destroy.
//
// Messages, not threads: a mediated thread is opened by staff approving a
// meeting request, before either side has typed anything, so an empty thread
// is not a conversation and must not block the delete. A purchase, by
// contrast, counts the moment it exists — a pending payment is still a payment
// somebody made.
func (s *Store) ForMarriageProfile(ctx context.Context, profileID int64) (MarriageProfileRecords, error) {
	var r MarriageProfileRecords
	if profileID <= 0 {
		return r, errors.New("profileID is required")
	}
	err := s.Pool.QueryRow(ctx, `
		SELECT
		  (SELECT COUNT(*) FROM marriage_chat_messages m
		     JOIN marriage_chat_threads t ON t.id = m.thread_id
		    WHERE t.profile_id = $1)                                   AS messages,
		  (SELECT COUNT(*) FROM marriage_subscription_purchases
		    WHERE profile_id = $1)                                     AS subscription_purchases`,
		profileID,
	).Scan(&r.Messages, &r.SubscriptionPurchases)
	if err != nil {
		return r, fmt.Errorf("count records for engagement profile %d: %w", profileID, err)
	}
	return r, nil
}

// ─── beneficiary_cases ──────────────────────────────────────────────────

// CaseRecords is what DELETE /api/admin/beneficiary_cases/:id would destroy.
//
// It is the second door onto the conversation ee50aae protected on the signup
// route: case_volunteer_chat_threads hangs off the CASE as well as the signup,
// so deleting the case walked straight around that guard.
//
// Documents are the files a beneficiary uploaded as proof — the evidence the
// case was verified on. The uploaded file survives on disk, but the row that
// says what it is, who uploaded it and which case it belongs to does not, and
// nothing can rebuild that.
type CaseRecords struct {
	Messages  int `json:"messages"`
	Documents int `json:"documents"`
}

// Any reports whether anything irreplaceable would be lost.
func (r CaseRecords) Any() bool { return r.Messages > 0 || r.Documents > 0 }

// ForCase counts what deleting one beneficiary case would destroy.
func (s *Store) ForCase(ctx context.Context, caseID int64) (CaseRecords, error) {
	var r CaseRecords
	if caseID <= 0 {
		return r, errors.New("caseID is required")
	}
	err := s.Pool.QueryRow(ctx, `
		SELECT
		  (SELECT COUNT(*) FROM case_volunteer_chat_messages m
		     JOIN case_volunteer_chat_threads t ON t.id = m.thread_id
		    WHERE t.case_id = $1)                                      AS messages,
		  (SELECT COUNT(*) FROM beneficiary_case_documents
		    WHERE case_id = $1)                                        AS documents`,
		caseID,
	).Scan(&r.Messages, &r.Documents)
	if err != nil {
		return r, fmt.Errorf("count records for beneficiary case %d: %w", caseID, err)
	}
	return r, nil
}

// ─── sponsorships ───────────────────────────────────────────────────────

// SponsorshipRecords is what DELETE /api/admin/sponsorships/:id would destroy
// that cannot be rebuilt.
//
// THIS ONE COUNTS PART OF THE CHILD TABLE, NOT ALL OF IT, and that is the
// point. sponsorship_schedule holds one row per due date, and
// sponsorshipschedule.Generate materialises those rows from the sponsorship's
// own recurrence rule (schedule_interval + next_due_date), is UNIQUE-guarded on
// (sponsorship_id, due_date) and is explicitly idempotent — "calling this
// repeatedly is safe … it simply tops the schedule back up". An unsettled
// occurrence is therefore a projection, not a record: it comes back by itself.
//
// A SETTLED occurrence is the opposite. 'paid' (with its paid_at) and
// 'skipped' record a decision somebody made about money on a date, and Generate
// will never recreate it — it only ever writes 'upcoming' rows forward from
// next_due_date. That is the row worth refusing over, and it is the same
// distinction ee50aae drew between a thread the system opens and a message a
// person wrote.
type SponsorshipRecords struct {
	SettledOccurrences int `json:"settled_occurrences"`
}

// Any reports whether anything irreplaceable would be lost.
func (r SponsorshipRecords) Any() bool { return r.SettledOccurrences > 0 }

// ForSponsorship counts the settled schedule occurrences a delete would take.
func (s *Store) ForSponsorship(ctx context.Context, sponsorshipID int64) (SponsorshipRecords, error) {
	var r SponsorshipRecords
	if sponsorshipID <= 0 {
		return r, errors.New("sponsorshipID is required")
	}
	// paid_at is checked alongside the status because a row can carry a
	// settlement timestamp while its status is being moved; either one is
	// evidence that money was accounted for on that date.
	err := s.Pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM sponsorship_schedule
		 WHERE sponsorship_id = $1
		   AND (status IN ('paid', 'skipped') OR paid_at IS NOT NULL)`,
		sponsorshipID,
	).Scan(&r.SettledOccurrences)
	if err != nil {
		return r, fmt.Errorf("count settled occurrences for sponsorship %d: %w", sponsorshipID, err)
	}
	return r, nil
}

// ─── beneficiary_project_requests ───────────────────────────────────────

// ProjectRequestRecords is what DELETE /api/admin/beneficiary_project_requests/:id
// would destroy that cannot be rebuilt.
//
// Comments are prose other people wrote, on somebody else's request, and
// deleting the request destroys them without their author ever acting. Already
// soft-deleted comments (is_deleted = 1) are not counted: they have already
// been withdrawn from view by their author or by staff, so nothing visible is
// lost with them.
//
// LIKES ARE DELIBERATELY NOT COUNTED. A like is one row of
// (request, user, created_at) with no authored content, no money and no
// evidentiary weight; it is a single tap that the same person can make again,
// and it is never shown as history — only as a total. Refusing a delete over a
// like would cost the operator the ability to remove a popular request while
// protecting nothing anyone could miss. This is a judgement, and it is recorded
// here rather than left implicit.
type ProjectRequestRecords struct {
	Comments int `json:"comments"`
}

// Any reports whether anything irreplaceable would be lost.
func (r ProjectRequestRecords) Any() bool { return r.Comments > 0 }

// ForProjectRequest counts the live comments a delete would take.
func (s *Store) ForProjectRequest(ctx context.Context, requestID int64) (ProjectRequestRecords, error) {
	var r ProjectRequestRecords
	if requestID <= 0 {
		return r, errors.New("requestID is required")
	}
	err := s.Pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM beneficiary_project_request_comments
		 WHERE project_request_id = $1 AND is_deleted = 0`,
		requestID,
	).Scan(&r.Comments)
	if err != nil {
		return r, fmt.Errorf("count comments for project request %d: %w", requestID, err)
	}
	return r, nil
}
