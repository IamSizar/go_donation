// contactblocks.go — K19's supervision record: the attempts to pass a phone
// number or an email address through the supervised donor↔beneficiary thread.
//
// Separate from chat.go on purpose. chat.go owns the thread lifecycle and is
// already at the file-size limit; this owns one small, self-contained concern
// (what was refused, and to whom it is shown) and is read on its own by anyone
// asking "what does the block actually keep?".
//
// The detection itself is not here — it is pure string work with no database in
// it, and lives in internal/moderation/contactfilter.go. This file only stores
// the verdict.
package chat

import (
	"context"
	"fmt"
	"time"

	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// ContactBlock is one refused message, as staff read it.
type ContactBlock struct {
	ID           int64   `json:"id"`
	ThreadID     int64   `json:"thread_id"`
	SenderUserID int64   `json:"sender_user_id"`
	SenderName   *string `json:"sender_name"`
	Kind         string  `json:"kind"`
	MatchCount   int     `json:"match_count"`
	// RedactedBody is the message with every contact detail replaced by "•••".
	// The raw body is never stored — see migration 116 for why.
	RedactedBody string    `json:"redacted_body"`
	CreatedAt    time.Time `json:"created_at"`
}

// RecordContactBlock appends one refused attempt.
//
// Deliberately returns its error rather than swallowing it, but the caller
// (handlers/chat_contact_block.go) logs and continues: failing to record the
// attempt must never turn into failing to BLOCK it. The refusal is the
// guarantee; the record is the supervision aid.
func (s *Store) RecordContactBlock(ctx context.Context, threadID, senderID int64, kind string, matchCount int, redactedBody string) error {
	if _, err := s.Pool.Exec(ctx, `
		INSERT INTO chat_contact_blocks (thread_id, sender_user_id, kind, match_count, redacted_body)
		VALUES ($1, $2, $3, $4, $5)`,
		threadID, senderID, kind, matchCount, redactedBody,
	); err != nil {
		return fmt.Errorf("recording contact block on thread %d: %w", threadID, err)
	}
	return nil
}

// ListContactBlocks returns one thread's refused attempts, newest first, with
// the sender's name resolved for the dashboard.
//
// No privacy masking is applied to the name, matching ListMessages (the raw
// admin view) rather than ListMessagesForViewer: this is a staff-only screen
// behind the `messages` permission, and a supervisor who cannot see WHO kept
// trying to pass a number out cannot act on it.
func (s *Store) ListContactBlocks(ctx context.Context, threadID int64) ([]ContactBlock, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT b.id, b.thread_id, b.sender_user_id, p.full_name,
		       b.kind, b.match_count, b.redacted_body, b.created_at
		  FROM chat_contact_blocks b
		  LEFT JOIN user_profiles p ON p.user_id = b.sender_user_id
		 WHERE b.thread_id = $1
		 ORDER BY b.id DESC`,
		threadID,
	)
	if err != nil {
		return nil, fmt.Errorf("listing contact blocks for thread %d: %w", threadID, err)
	}
	defer rows.Close()
	out := []ContactBlock{}
	for rows.Next() {
		var b ContactBlock
		if err := rows.Scan(&b.ID, &b.ThreadID, &b.SenderUserID, &b.SenderName,
			&b.Kind, &b.MatchCount, &b.RedactedBody, &b.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning contact block: %w", err)
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// withholdPeerPhone decides whether the counterpart's phone number is stripped
// from a thread list row.
//
// # WHY THIS EXISTS AT ALL
//
// Without it the write-path filter is theatre. ScanContact refuses a message
// carrying a phone number, but GET /api/chats was handing the counterpart's
// real number over in the row ABOVE that conversation — subject only to the
// counterpart's own privacy toggle, which is off by default. Blocking the
// exchange while serving the number is not protection.
//
// # WHY ONLY THE PHONE
//
// The name stays. The app renders it as the conversation title, it is already
// governed by the K8 privacy system, and withholding it is a product decision
// about whether these two people may know who they are talking to — not a leak
// fix. The phone is different: the app parses it and never displays it, so it
// was travelling for no reason at all.
//
// Peer threads only, matching the write-path filter exactly: on a SUPPORT
// thread the counterpart is staff, and that is not the pair K19 is about.
func withholdPeerPhone(viewerIsOrdinary bool, otherTier *string) bool {
	if !viewerIsOrdinary {
		return false // staff reading their own list keep the full row
	}
	tier := ""
	if otherTier != nil {
		tier = *otherTier
	}
	return permissions.TierFrom(tier) == permissions.TierUser
}

// isOrdinaryUser reports whether a user holds no dashboard tier. Fails CLOSED
// (reports true) for the same reason as IsPeerThread: the safe direction is
// withholding a number, not serving one.
func (s *Store) isOrdinaryUser(ctx context.Context, userID int64) (bool, error) {
	var tier *string
	if err := s.Pool.QueryRow(ctx,
		`SELECT staff_tier FROM users WHERE id = $1`, userID).Scan(&tier); err != nil {
		return true, fmt.Errorf("loading tier for user %d: %w", userID, err)
	}
	t := ""
	if tier != nil {
		t = *tier
	}
	return permissions.TierFrom(t) == permissions.TierUser, nil
}

// IsPeerThread reports whether BOTH parties of a thread are ordinary app users
// — i.e. neither holds a dashboard staff_tier.
//
// This is the switch that decides whether the contact filter runs at all, and
// it is the reason the filter does not break support.
//
// The same chat_threads table carries two very different conversations. A
// donor↔beneficiary thread is the one K19 is about: two members of the public,
// where an exchanged phone number is the extortion risk the client named. But
// POST /api/chats/support (#45) opens a thread on this SAME table whose "owner"
// is the configured support account — and a user telling support their own
// phone number is the support channel doing its job. Filtering by endpoint
// would have been wrong (both use the same PostMessage handler); filtering by
// who the parties ARE is the distinction that actually matters.
//
// staff_tier is the sole authority here. is_admin is legacy and is not read.
//
// Fails CLOSED: on a query error it reports true (filter ON), because the
// failure mode of filtering a support message is a confused user, while the
// failure mode of not filtering a donor↔beneficiary message is the exact leak
// this row exists to prevent.
func (s *Store) IsPeerThread(ctx context.Context, t Thread) (bool, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT staff_tier FROM users WHERE id = ANY($1)`,
		[]int64{t.DonorUserID, t.OwnerUserID})
	if err != nil {
		return true, fmt.Errorf("loading thread %d party tiers: %w", t.ID, err)
	}
	defer rows.Close()
	for rows.Next() {
		var tier *string
		if err := rows.Scan(&tier); err != nil {
			return true, fmt.Errorf("scanning party tier: %w", err)
		}
		s := ""
		if tier != nil {
			s = *tier
		}
		if permissions.TierFrom(s) != permissions.TierUser {
			return false, nil // a staff party — not a peer thread
		}
	}
	if err := rows.Err(); err != nil {
		return true, fmt.Errorf("reading thread %d party tiers: %w", t.ID, err)
	}
	return true, nil
}
