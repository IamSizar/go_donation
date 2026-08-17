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
