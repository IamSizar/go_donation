// Package chat implements the donor ↔ campaign-owner consent-based chat.
//
// A thread is opened by either party and starts 'pending'; the OTHER party
// accepts it from their Alerts tab, flipping it to 'active'. Once active, the
// donor, the owner (beneficiary), and any admin (as "support") can post
// messages. There is exactly one thread per (donor, owner) pair.
package chat

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Sender role codes stored on each message (snapshot at send time).
const (
	RoleSupport = 0 // admin replying as support
)

var (
	ErrNotFound       = errors.New("thread not found")
	ErrNotParty       = errors.New("you are not a participant in this chat")
	ErrNotRecipient   = errors.New("only the invited party can accept or decline")
	ErrNotActive      = errors.New("this chat is not active yet")
	ErrAlreadyClaimed = errors.New("this chat is already claimed by another staff member")
)

// Thread is the raw row.
type Thread struct {
	ID          int64  `json:"id"`
	DonorUserID int64  `json:"donor_user_id"`
	OwnerUserID int64  `json:"owner_user_id"`
	CampaignID  *int64 `json:"campaign_id"`
	Status      string `json:"status"`
	InitiatedBy int64  `json:"initiated_by"`
	// Note #36 — the specific staff member who has claimed this thread, so a
	// donor/beneficiary sees a named "Responsible Staff Member" instead of an
	// anonymous "Support" relay. Nil = unclaimed (any admin may still reply).
	AssignedStaffUserID *int64    `json:"assigned_staff_user_id"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// ThreadView is a thread enriched for one viewing user: the OTHER party's
// identity, the last message, and the viewer's unread count.
type ThreadView struct {
	ID              int64   `json:"id"`
	Status          string  `json:"status"`
	CampaignID      *int64  `json:"campaign_id"`
	CampaignTitle   *string `json:"campaign_title"`
	InitiatedBy     int64   `json:"initiated_by"`
	MyRole          string  `json:"my_role"`          // "donor" | "owner"
	IncomingPending bool    `json:"incoming_pending"` // pending AND I'm the one who must accept
	OtherUserID     int64   `json:"other_user_id"`
	OtherName       *string `json:"other_name"`
	OtherPhone      *string `json:"other_phone"`
	// Note #36 — the claimed staff member's name, if any (nil = unclaimed).
	AssignedStaffName *string    `json:"assigned_staff_name"`
	LastMessage       *string    `json:"last_message"`
	LastMessageAt     *time.Time `json:"last_message_at"`
	UnreadCount       int        `json:"unread_count"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// Message is one chat message with the sender's display name.
type Message struct {
	ID           int64     `json:"id"`
	ThreadID     int64     `json:"thread_id"`
	SenderUserID int64     `json:"sender_user_id"`
	SenderRole   int       `json:"sender_role"`
	SenderName   *string   `json:"sender_name"`
	Body         string    `json:"body"`
	CreatedAt    time.Time `json:"created_at"`
}

// RequestThread opens (or re-opens) a pending thread between a donor and an
// owner. initiatorID must equal donorID or ownerID (validated by the caller).
// Returns the thread, the recipient's user id (the party who must accept), and
// whether a fresh request was created (true → caller should notify recipient).
func (s *Store) RequestThread(ctx context.Context, donorID, ownerID int64, campaignID *int64, initiatorID int64) (Thread, int64, bool, error) {
	var t Thread
	recipient := ownerID
	if initiatorID == ownerID {
		recipient = donorID
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return t, 0, false, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	err = tx.QueryRow(ctx, `
		SELECT id, donor_user_id, owner_user_id, campaign_id, status, initiated_by, assigned_staff_user_id, created_at, updated_at
		  FROM chat_threads
		 WHERE donor_user_id = $1 AND owner_user_id = $2
		 FOR UPDATE`,
		donorID, ownerID,
	).Scan(&t.ID, &t.DonorUserID, &t.OwnerUserID, &t.CampaignID, &t.Status, &t.InitiatedBy, &t.AssignedStaffUserID, &t.CreatedAt, &t.UpdatedAt)

	switch {
	case errors.Is(err, pgx.ErrNoRows):
		// Brand-new request.
		if err := tx.QueryRow(ctx, `
			INSERT INTO chat_threads (donor_user_id, owner_user_id, campaign_id, status, initiated_by)
			VALUES ($1, $2, $3, 'pending', $4)
			RETURNING id, donor_user_id, owner_user_id, campaign_id, status, initiated_by, assigned_staff_user_id, created_at, updated_at`,
			donorID, ownerID, campaignID, initiatorID,
		).Scan(&t.ID, &t.DonorUserID, &t.OwnerUserID, &t.CampaignID, &t.Status, &t.InitiatedBy, &t.AssignedStaffUserID, &t.CreatedAt, &t.UpdatedAt); err != nil {
			return t, 0, false, err
		}
		if err := tx.Commit(ctx); err != nil {
			return t, 0, false, err
		}
		return t, recipient, true, nil
	case err != nil:
		return t, 0, false, err
	}

	// A thread already exists.
	if t.Status == "declined" {
		// Re-open as a fresh pending request from this initiator.
		if err := tx.QueryRow(ctx, `
			UPDATE chat_threads
			   SET status = 'pending', initiated_by = $2,
			       campaign_id = COALESCE($3, campaign_id), updated_at = CURRENT_TIMESTAMP
			 WHERE id = $1
			RETURNING id, donor_user_id, owner_user_id, campaign_id, status, initiated_by, assigned_staff_user_id, created_at, updated_at`,
			t.ID, initiatorID, campaignID,
		).Scan(&t.ID, &t.DonorUserID, &t.OwnerUserID, &t.CampaignID, &t.Status, &t.InitiatedBy, &t.AssignedStaffUserID, &t.CreatedAt, &t.UpdatedAt); err != nil {
			return t, 0, false, err
		}
		if err := tx.Commit(ctx); err != nil {
			return t, 0, false, err
		}
		return t, recipient, true, nil
	}

	// Already pending or active — nothing to do, no new notification.
	if err := tx.Commit(ctx); err != nil {
		return t, 0, false, err
	}
	return t, recipient, false, nil
}

// AcceptThread flips a pending thread to active. Only the recipient (the party
// who did NOT initiate) may accept. Returns the thread and the initiator id so
// the caller can notify them.
func (s *Store) AcceptThread(ctx context.Context, threadID, userID int64) (Thread, int64, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, 0, err
	}
	if userID != t.DonorUserID && userID != t.OwnerUserID {
		return t, 0, ErrNotParty
	}
	if userID == t.InitiatedBy {
		return t, 0, ErrNotRecipient
	}
	if t.Status == "active" {
		return t, t.InitiatedBy, nil // idempotent
	}
	if err := s.Pool.QueryRow(ctx, `
		UPDATE chat_threads SET status = 'active', updated_at = CURRENT_TIMESTAMP
		 WHERE id = $1
		RETURNING id, donor_user_id, owner_user_id, campaign_id, status, initiated_by, assigned_staff_user_id, created_at, updated_at`,
		threadID,
	).Scan(&t.ID, &t.DonorUserID, &t.OwnerUserID, &t.CampaignID, &t.Status, &t.InitiatedBy, &t.AssignedStaffUserID, &t.CreatedAt, &t.UpdatedAt); err != nil {
		return t, 0, err
	}
	return t, t.InitiatedBy, nil
}

// DeclineThread marks a pending thread declined. Only the recipient may decline.
func (s *Store) DeclineThread(ctx context.Context, threadID, userID int64) (Thread, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, err
	}
	if userID != t.DonorUserID && userID != t.OwnerUserID {
		return t, ErrNotParty
	}
	if userID == t.InitiatedBy {
		return t, ErrNotRecipient
	}
	_, err = s.Pool.Exec(ctx, `
		UPDATE chat_threads SET status = 'declined', updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
		threadID)
	t.Status = "declined"
	return t, err
}

// GetThread loads one raw thread row.
func (s *Store) GetThread(ctx context.Context, threadID int64) (Thread, error) {
	var t Thread
	err := s.Pool.QueryRow(ctx, `
		SELECT id, donor_user_id, owner_user_id, campaign_id, status, initiated_by, assigned_staff_user_id, created_at, updated_at
		  FROM chat_threads WHERE id = $1`,
		threadID,
	).Scan(&t.ID, &t.DonorUserID, &t.OwnerUserID, &t.CampaignID, &t.Status, &t.InitiatedBy, &t.AssignedStaffUserID, &t.CreatedAt, &t.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return t, ErrNotFound
	}
	return t, err
}

// IsParticipant reports whether userID is the donor or owner of the thread.
func (t Thread) IsParticipant(userID int64) bool {
	return userID == t.DonorUserID || userID == t.OwnerUserID
}

// ClaimThread assigns a specific staff member as this thread's "Responsible
// Staff Member" (Note #36) — so the donor/beneficiary see a real name instead
// of anonymous "Support". Only succeeds when the thread is currently
// unclaimed (or already claimed by the same staff member — idempotent);
// returns ErrAlreadyClaimed otherwise.
func (s *Store) ClaimThread(ctx context.Context, threadID, staffUserID int64) (Thread, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, err
	}
	if t.AssignedStaffUserID != nil && *t.AssignedStaffUserID != staffUserID {
		return t, ErrAlreadyClaimed
	}
	if _, err := s.Pool.Exec(ctx,
		`UPDATE chat_threads SET assigned_staff_user_id = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
		threadID, staffUserID); err != nil {
		return t, err
	}
	t.AssignedStaffUserID = &staffUserID
	return t, nil
}

// ReleaseThread clears the claim, returning the thread to "any admin may
// reply anonymously as Support."
func (s *Store) ReleaseThread(ctx context.Context, threadID int64) (Thread, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, err
	}
	if _, err := s.Pool.Exec(ctx,
		`UPDATE chat_threads SET assigned_staff_user_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
		threadID); err != nil {
		return t, err
	}
	t.AssignedStaffUserID = nil
	return t, nil
}

// ListThreadsForUser returns every thread the user belongs to (as donor or
// owner), newest-activity first, with the other party + last message + unread.
func (s *Store) ListThreadsForUser(ctx context.Context, userID int64) ([]ThreadView, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id, t.status, t.campaign_id, c.title, t.initiated_by, t.updated_at,
		       CASE WHEN t.donor_user_id = $1 THEN 'donor' ELSE 'owner' END AS my_role,
		       CASE WHEN t.donor_user_id = $1 THEN t.owner_user_id ELSE t.donor_user_id END AS other_id,
		       op.full_name, ou.phone,
		       sp.full_name AS assigned_staff_name,
		       lm.body, lm.created_at,
		       COALESCE((
		         SELECT COUNT(*) FROM chat_messages m
		          WHERE m.thread_id = t.id
		            AND m.sender_user_id <> $1
		            AND m.id > COALESCE((SELECT last_read_msg_id FROM chat_reads r
		                                  WHERE r.thread_id = t.id AND r.user_id = $1), 0)
		       ), 0) AS unread
		  FROM chat_threads t
		  LEFT JOIN campaigns c ON c.id = t.campaign_id
		  LEFT JOIN users ou ON ou.id = (CASE WHEN t.donor_user_id = $1 THEN t.owner_user_id ELSE t.donor_user_id END)
		  LEFT JOIN user_profiles op ON op.user_id = (CASE WHEN t.donor_user_id = $1 THEN t.owner_user_id ELSE t.donor_user_id END)
		  LEFT JOIN user_profiles sp ON sp.user_id = t.assigned_staff_user_id
		  LEFT JOIN LATERAL (
		      SELECT body, created_at FROM chat_messages m
		       WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1
		  ) lm ON TRUE
		 WHERE (t.donor_user_id = $1 OR t.owner_user_id = $1)
		   AND t.status <> 'declined'
		 ORDER BY t.updated_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ThreadView{}
	for rows.Next() {
		var v ThreadView
		if err := rows.Scan(&v.ID, &v.Status, &v.CampaignID, &v.CampaignTitle, &v.InitiatedBy, &v.UpdatedAt,
			&v.MyRole, &v.OtherUserID, &v.OtherName, &v.OtherPhone, &v.AssignedStaffName,
			&v.LastMessage, &v.LastMessageAt, &v.UnreadCount); err != nil {
			return nil, err
		}
		v.IncomingPending = v.Status == "pending" && v.InitiatedBy != userID
		out = append(out, v)
	}
	return out, rows.Err()
}

// ListMessages returns all messages in a thread oldest-first, with sender name.
func (s *Store) ListMessages(ctx context.Context, threadID int64) ([]Message, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT m.id, m.thread_id, m.sender_user_id, m.sender_role, p.full_name, m.body, m.created_at
		  FROM chat_messages m
		  LEFT JOIN user_profiles p ON p.user_id = m.sender_user_id
		 WHERE m.thread_id = $1
		 ORDER BY m.id ASC`,
		threadID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.ThreadID, &m.SenderUserID, &m.SenderRole, &m.SenderName, &m.Body, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// PostMessage inserts a message and bumps the thread's updated_at. The caller
// must have verified the sender is allowed to post (active thread; participant
// or admin).
func (s *Store) PostMessage(ctx context.Context, threadID, senderID int64, senderRole int, body string) (Message, error) {
	var m Message
	body = strings.TrimSpace(body)
	if body == "" {
		return m, errors.New("empty message")
	}
	if len([]rune(body)) > 4000 {
		body = string([]rune(body)[:4000])
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return m, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := tx.QueryRow(ctx, `
		INSERT INTO chat_messages (thread_id, sender_user_id, sender_role, body)
		VALUES ($1, $2, $3, $4)
		RETURNING id, thread_id, sender_user_id, sender_role, body, created_at`,
		threadID, senderID, senderRole, body,
	).Scan(&m.ID, &m.ThreadID, &m.SenderUserID, &m.SenderRole, &m.Body, &m.CreatedAt); err != nil {
		return m, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE chat_threads SET updated_at = CURRENT_TIMESTAMP WHERE id = $1`, threadID); err != nil {
		return m, err
	}
	// Sender has implicitly read their own message.
	if _, err := tx.Exec(ctx, `
		INSERT INTO chat_reads (thread_id, user_id, last_read_msg_id) VALUES ($1, $2, $3)
		ON CONFLICT (thread_id, user_id) DO UPDATE SET last_read_msg_id = GREATEST(chat_reads.last_read_msg_id, EXCLUDED.last_read_msg_id)`,
		threadID, senderID, m.ID); err != nil {
		return m, err
	}
	if err := tx.Commit(ctx); err != nil {
		return m, err
	}
	return m, nil
}

// MarkRead advances a user's read cursor to the newest message in the thread.
func (s *Store) MarkRead(ctx context.Context, threadID, userID int64) error {
	_, err := s.Pool.Exec(ctx, `
		INSERT INTO chat_reads (thread_id, user_id, last_read_msg_id)
		VALUES ($1, $2, COALESCE((SELECT MAX(id) FROM chat_messages WHERE thread_id = $1), 0))
		ON CONFLICT (thread_id, user_id)
		DO UPDATE SET last_read_msg_id = COALESCE((SELECT MAX(id) FROM chat_messages WHERE thread_id = $1), 0)`,
		threadID, userID)
	return err
}

// CounterpartIDs returns the donor + owner ids (used to notify the other party
// on a new message).
func (t Thread) CounterpartIDs(senderID int64) []int64 {
	out := []int64{}
	if t.DonorUserID != senderID {
		out = append(out, t.DonorUserID)
	}
	if t.OwnerUserID != senderID {
		out = append(out, t.OwnerUserID)
	}
	return out
}

// ===== Admin =====

// AdminThreadView is the admin list row: both parties + counts.
type AdminThreadView struct {
	ID            int64   `json:"id"`
	Status        string  `json:"status"`
	CampaignID    *int64  `json:"campaign_id"`
	CampaignTitle *string `json:"campaign_title"`
	DonorUserID   int64   `json:"donor_user_id"`
	DonorName     *string `json:"donor_name"`
	DonorPhone    *string `json:"donor_phone"`
	OwnerUserID   int64   `json:"owner_user_id"`
	OwnerName     *string `json:"owner_name"`
	OwnerPhone    *string `json:"owner_phone"`
	// Note #36 — the claimed "Responsible Staff Member," if any.
	AssignedStaffUserID *int64     `json:"assigned_staff_user_id"`
	AssignedStaffName   *string    `json:"assigned_staff_name"`
	MessageCount        int        `json:"message_count"`
	LastMessage         *string    `json:"last_message"`
	LastMessageAt       *time.Time `json:"last_message_at"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}

// ListAllThreads returns every thread for the admin Messages page.
func (s *Store) ListAllThreads(ctx context.Context, q string) ([]AdminThreadView, error) {
	args := []any{}
	where := "WHERE 1=1"
	if t := strings.TrimSpace(q); t != "" {
		args = append(args, "%"+t+"%")
		where += ` AND (dp.full_name ILIKE $1 OR opf.full_name ILIKE $1 OR c.title ILIKE $1)`
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id, t.status, t.campaign_id, c.title,
		       t.donor_user_id, dp.full_name, du.phone,
		       t.owner_user_id, opf.full_name, ou.phone,
		       t.assigned_staff_user_id, sp.full_name,
		       COALESCE((SELECT COUNT(*) FROM chat_messages m WHERE m.thread_id = t.id), 0),
		       lm.body, lm.created_at,
		       t.created_at, t.updated_at
		  FROM chat_threads t
		  LEFT JOIN campaigns c ON c.id = t.campaign_id
		  LEFT JOIN users du ON du.id = t.donor_user_id
		  LEFT JOIN user_profiles dp ON dp.user_id = t.donor_user_id
		  LEFT JOIN users ou ON ou.id = t.owner_user_id
		  LEFT JOIN user_profiles opf ON opf.user_id = t.owner_user_id
		  LEFT JOIN user_profiles sp ON sp.user_id = t.assigned_staff_user_id
		  LEFT JOIN LATERAL (
		     SELECT body, created_at FROM chat_messages m
		      WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1
		  ) lm ON TRUE
		  `+where+`
		 ORDER BY t.updated_at DESC`,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []AdminThreadView{}
	for rows.Next() {
		var v AdminThreadView
		if err := rows.Scan(&v.ID, &v.Status, &v.CampaignID, &v.CampaignTitle,
			&v.DonorUserID, &v.DonorName, &v.DonorPhone,
			&v.OwnerUserID, &v.OwnerName, &v.OwnerPhone,
			&v.AssignedStaffUserID, &v.AssignedStaffName,
			&v.MessageCount, &v.LastMessage, &v.LastMessageAt,
			&v.CreatedAt, &v.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
