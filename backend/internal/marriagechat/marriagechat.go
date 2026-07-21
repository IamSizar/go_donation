// Package marriagechat implements Note #35's staff-mediated chat for
// Marriage-section meeting requests.
//
// Lifecycle: a user requests a meeting about a profile (marriage.RequestMeeting,
// unchanged) → staff review the request in the admin dashboard and Approve or
// Decline it → approving opens a marriage_chat_threads row 'pending' → the
// PROFILE OWNER must accept it before either side can post → once 'active',
// the requester, the owner, and any admin (as "staff") can post messages.
//
// Privacy: unlike the donor↔owner chat (internal/chat), this is designed so
// neither non-staff party ever learns the other's real identity. Every
// message is tagged with a role ('requester'|'owner'|'staff'), not resolved
// to a name for mobile responses — ListMessages/ListThreadsForUser (the
// mobile-facing methods) never SELECT or return sender_user_id, full_name, or
// phone for the counterpart. Only the Admin* methods join real identities,
// for staff oversight.
package marriagechat

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

var (
	ErrNotFound    = errors.New("thread not found")
	ErrNotParty    = errors.New("you are not a participant in this chat")
	ErrNotOwner    = errors.New("only the profile owner can accept or decline")
	ErrNotActive   = errors.New("this chat is not active yet")
	ErrRequestGone = errors.New("meeting request not found or already decided")
)

// MeetingRequestView is one row for the admin's meeting-requests inbox.
type MeetingRequestView struct {
	ID          int64      `json:"id"`
	FromUserID  int64      `json:"from_user_id"`
	FromName    *string    `json:"from_name"`
	FromPhone   *string    `json:"from_phone"`
	ProfileID   int64      `json:"profile_id"`
	ProfileCode string     `json:"profile_code"`
	OwnerUserID int64      `json:"owner_user_id"`
	OwnerName   *string    `json:"owner_name"`
	OwnerPhone  *string    `json:"owner_phone"`
	Message     *string    `json:"message"`
	Status      string     `json:"status"` // pending | approved | declined
	ThreadID    *int64     `json:"thread_id"`
	CreatedAt   time.Time  `json:"created_at"`
	DecidedAt   *time.Time `json:"decided_at"`
}

// ListMeetingRequests returns every meeting request for the admin inbox, newest first.
func (s *Store) ListMeetingRequests(ctx context.Context) ([]MeetingRequestView, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT r.id, r.from_user_id, fp.full_name, fu.phone,
		       r.profile_id, mp.profile_code, mp.user_id,
		       op.full_name, ou.phone,
		       r.message, r.status, r.thread_id, r.created_at, r.decided_at
		  FROM marriage_meeting_requests r
		  JOIN marriage_profiles mp ON mp.id = r.profile_id
		  LEFT JOIN users fu ON fu.id = r.from_user_id
		  LEFT JOIN user_profiles fp ON fp.user_id = r.from_user_id
		  LEFT JOIN users ou ON ou.id = mp.user_id
		  LEFT JOIN user_profiles op ON op.user_id = mp.user_id
		 ORDER BY r.created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []MeetingRequestView{}
	for rows.Next() {
		var v MeetingRequestView
		if err := rows.Scan(&v.ID, &v.FromUserID, &v.FromName, &v.FromPhone,
			&v.ProfileID, &v.ProfileCode, &v.OwnerUserID,
			&v.OwnerName, &v.OwnerPhone,
			&v.Message, &v.Status, &v.ThreadID, &v.CreatedAt, &v.DecidedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// ApproveMeetingRequest opens (or reuses) a thread for a pending meeting
// request and marks the request approved. Returns the thread and the profile
// owner's user id (the party who must accept next, to notify).
func (s *Store) ApproveMeetingRequest(ctx context.Context, requestID, staffUserID int64) (Thread, int64, error) {
	var t Thread
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return t, 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var fromUserID, profileID, ownerUserID int64
	err = tx.QueryRow(ctx, `
		SELECT r.from_user_id, r.profile_id, mp.user_id
		  FROM marriage_meeting_requests r
		  JOIN marriage_profiles mp ON mp.id = r.profile_id
		 WHERE r.id = $1 AND r.status = 'pending'
		 FOR UPDATE OF r`,
		requestID,
	).Scan(&fromUserID, &profileID, &ownerUserID)
	if errors.Is(err, pgx.ErrNoRows) {
		return t, 0, ErrRequestGone
	}
	if err != nil {
		return t, 0, err
	}
	if fromUserID == ownerUserID {
		return t, 0, errors.New("requester cannot be the profile owner")
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO marriage_chat_threads (meeting_request_id, profile_id, requester_user_id, owner_user_id, status)
		VALUES ($1, $2, $3, $4, 'pending')
		ON CONFLICT (requester_user_id, profile_id) DO UPDATE
		  SET meeting_request_id = EXCLUDED.meeting_request_id
		RETURNING id, meeting_request_id, profile_id, requester_user_id, owner_user_id, status, created_at, updated_at`,
		requestID, profileID, fromUserID, ownerUserID,
	).Scan(&t.ID, &t.MeetingRequestID, &t.ProfileID, &t.RequesterUserID, &t.OwnerUserID, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	if err != nil {
		return t, 0, err
	}

	if _, err := tx.Exec(ctx, `
		UPDATE marriage_meeting_requests
		   SET status = 'approved', thread_id = $2, decided_at = CURRENT_TIMESTAMP, decided_by = $3
		 WHERE id = $1`,
		requestID, t.ID, staffUserID,
	); err != nil {
		return t, 0, err
	}

	if err := tx.Commit(ctx); err != nil {
		return t, 0, err
	}
	return t, ownerUserID, nil
}

// DeclineMeetingRequest marks a pending request declined (no thread opened).
// Returns the requester's user id, to notify.
func (s *Store) DeclineMeetingRequest(ctx context.Context, requestID, staffUserID int64) (int64, error) {
	var fromUserID int64
	err := s.Pool.QueryRow(ctx, `
		UPDATE marriage_meeting_requests
		   SET status = 'declined', decided_at = CURRENT_TIMESTAMP, decided_by = $2
		 WHERE id = $1 AND status = 'pending'
		RETURNING from_user_id`,
		requestID, staffUserID,
	).Scan(&fromUserID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrRequestGone
	}
	return fromUserID, err
}

// Thread is the raw row.
type Thread struct {
	ID               int64     `json:"id"`
	MeetingRequestID int64     `json:"meeting_request_id"`
	ProfileID        int64     `json:"profile_id"`
	RequesterUserID  int64     `json:"requester_user_id"`
	OwnerUserID      int64     `json:"owner_user_id"`
	Status           string    `json:"status"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

func (t Thread) IsParticipant(userID int64) bool {
	return userID == t.RequesterUserID || userID == t.OwnerUserID
}

// RoleFor returns the sender_role to store for a participant posting a
// message (never called for staff — callers pass RoleStaff directly).
func (t Thread) RoleFor(userID int64) string {
	if userID == t.OwnerUserID {
		return RoleOwner
	}
	return RoleRequester
}

const (
	RoleRequester = "requester"
	RoleOwner     = "owner"
	RoleStaff     = "staff"
)

func (s *Store) GetThread(ctx context.Context, threadID int64) (Thread, error) {
	var t Thread
	err := s.Pool.QueryRow(ctx, `
		SELECT id, meeting_request_id, profile_id, requester_user_id, owner_user_id, status, created_at, updated_at
		  FROM marriage_chat_threads WHERE id = $1`,
		threadID,
	).Scan(&t.ID, &t.MeetingRequestID, &t.ProfileID, &t.RequesterUserID, &t.OwnerUserID, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return t, ErrNotFound
	}
	return t, err
}

// AcceptThread flips a pending thread to active. Only the profile owner may accept.
func (s *Store) AcceptThread(ctx context.Context, threadID, userID int64) (Thread, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, err
	}
	if userID != t.OwnerUserID {
		return t, ErrNotOwner
	}
	if t.Status == "active" {
		return t, nil // idempotent
	}
	err = s.Pool.QueryRow(ctx, `
		UPDATE marriage_chat_threads SET status = 'active', updated_at = CURRENT_TIMESTAMP
		 WHERE id = $1
		RETURNING id, meeting_request_id, profile_id, requester_user_id, owner_user_id, status, created_at, updated_at`,
		threadID,
	).Scan(&t.ID, &t.MeetingRequestID, &t.ProfileID, &t.RequesterUserID, &t.OwnerUserID, &t.Status, &t.CreatedAt, &t.UpdatedAt)
	return t, err
}

// DeclineThread marks an active/pending thread declined. Only the profile owner may decline.
func (s *Store) DeclineThread(ctx context.Context, threadID, userID int64) (Thread, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, err
	}
	if userID != t.OwnerUserID {
		return t, ErrNotOwner
	}
	_, err = s.Pool.Exec(ctx,
		`UPDATE marriage_chat_threads SET status = 'declined', updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
		threadID)
	t.Status = "declined"
	return t, err
}

// ThreadView is a thread enriched for one viewing (non-staff) user. The
// counterpart is intentionally never named — OtherLabel is either the
// profile's own (already-public) profile_code (shown to the requester) or a
// generic "interested member" placeholder (shown to the owner).
type ThreadView struct {
	ID            int64      `json:"id"`
	Status        string     `json:"status"`
	MyRole        string     `json:"my_role"` // "requester" | "owner"
	OtherLabel    string     `json:"other_label"`
	LastMessage   *string    `json:"last_message"`
	LastMessageAt *time.Time `json:"last_message_at"`
	UnreadCount   int        `json:"unread_count"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

// ListThreadsForUser returns every thread the user belongs to, newest-activity first.
func (s *Store) ListThreadsForUser(ctx context.Context, userID int64) ([]ThreadView, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id, t.status, t.updated_at,
		       CASE WHEN t.requester_user_id = $1 THEN 'requester' ELSE 'owner' END AS my_role,
		       mp.profile_code,
		       lm.body, lm.created_at,
		       COALESCE((
		         SELECT COUNT(*) FROM marriage_chat_messages m
		          WHERE m.thread_id = t.id
		            AND m.sender_user_id <> $1
		            AND m.id > COALESCE((SELECT last_read_msg_id FROM marriage_chat_reads r
		                                  WHERE r.thread_id = t.id AND r.user_id = $1), 0)
		       ), 0) AS unread
		  FROM marriage_chat_threads t
		  JOIN marriage_profiles mp ON mp.id = t.profile_id
		  LEFT JOIN LATERAL (
		      SELECT body, created_at FROM marriage_chat_messages m
		       WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1
		  ) lm ON TRUE
		 WHERE (t.requester_user_id = $1 OR t.owner_user_id = $1)
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
		var profileCode string
		if err := rows.Scan(&v.ID, &v.Status, &v.UpdatedAt, &v.MyRole, &profileCode,
			&v.LastMessage, &v.LastMessageAt, &v.UnreadCount); err != nil {
			return nil, err
		}
		if v.MyRole == "requester" {
			v.OtherLabel = profileCode
		} else {
			v.OtherLabel = "interested_member" // app localizes this key
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// Message is one chat message as returned to a non-staff participant — no
// real identity, only the sender's role relative to the viewer.
type Message struct {
	ID         int64     `json:"id"`
	ThreadID   int64     `json:"thread_id"`
	SenderRole string    `json:"sender_role"` // requester | owner | staff
	IsMine     bool      `json:"is_mine"`
	Body       string    `json:"body"`
	CreatedAt  time.Time `json:"created_at"`
}

// ListMessages returns all messages in a thread oldest-first, for a specific
// viewer — IsMine is computed per-viewer; no sender_user_id is ever exposed.
func (s *Store) ListMessages(ctx context.Context, threadID, viewerUserID int64) ([]Message, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT id, thread_id, sender_user_id, sender_role, body, created_at
		  FROM marriage_chat_messages
		 WHERE thread_id = $1
		 ORDER BY id ASC`,
		threadID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		var m Message
		var senderUserID int64
		if err := rows.Scan(&m.ID, &m.ThreadID, &senderUserID, &m.SenderRole, &m.Body, &m.CreatedAt); err != nil {
			return nil, err
		}
		m.IsMine = senderUserID == viewerUserID
		out = append(out, m)
	}
	return out, rows.Err()
}

// PostMessage inserts a message and bumps the thread's updated_at. The caller
// must have verified the sender is allowed to post (active thread; participant
// or staff) and computed the correct role.
func (s *Store) PostMessage(ctx context.Context, threadID, senderID int64, role, body string) (Message, int64, error) {
	var m Message
	body = strings.TrimSpace(body)
	if body == "" {
		return m, 0, errors.New("empty message")
	}
	if len([]rune(body)) > 4000 {
		body = string([]rune(body)[:4000])
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return m, 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var id int64
	var createdAt time.Time
	if err := tx.QueryRow(ctx, `
		INSERT INTO marriage_chat_messages (thread_id, sender_user_id, sender_role, body)
		VALUES ($1, $2, $3, $4)
		RETURNING id, created_at`,
		threadID, senderID, role, body,
	).Scan(&id, &createdAt); err != nil {
		return m, 0, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE marriage_chat_threads SET updated_at = CURRENT_TIMESTAMP WHERE id = $1`, threadID); err != nil {
		return m, 0, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO marriage_chat_reads (thread_id, user_id, last_read_msg_id) VALUES ($1, $2, $3)
		ON CONFLICT (thread_id, user_id) DO UPDATE SET last_read_msg_id = GREATEST(marriage_chat_reads.last_read_msg_id, EXCLUDED.last_read_msg_id)`,
		threadID, senderID, id); err != nil {
		return m, 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return m, 0, err
	}
	m = Message{ID: id, ThreadID: threadID, SenderRole: role, IsMine: true, Body: body, CreatedAt: createdAt}
	return m, id, nil
}

// MarkRead advances a user's read cursor to the newest message in the thread.
func (s *Store) MarkRead(ctx context.Context, threadID, userID int64) error {
	_, err := s.Pool.Exec(ctx, `
		INSERT INTO marriage_chat_reads (thread_id, user_id, last_read_msg_id)
		VALUES ($1, $2, COALESCE((SELECT MAX(id) FROM marriage_chat_messages WHERE thread_id = $1), 0))
		ON CONFLICT (thread_id, user_id)
		DO UPDATE SET last_read_msg_id = COALESCE((SELECT MAX(id) FROM marriage_chat_messages WHERE thread_id = $1), 0)`,
		threadID, userID)
	return err
}

// CounterpartIDs returns the requester + owner ids other than senderID (used
// to notify the other real party on a new message; staff sends never notify
// "staff" since staff isn't a fixed participant).
func (t Thread) CounterpartIDs(senderID int64) []int64 {
	out := []int64{}
	if t.RequesterUserID != senderID {
		out = append(out, t.RequesterUserID)
	}
	if t.OwnerUserID != senderID {
		out = append(out, t.OwnerUserID)
	}
	return out
}

// ===== Admin =====

// AdminThreadView is the admin list row: both real parties + counts.
type AdminThreadView struct {
	ID              int64      `json:"id"`
	Status          string     `json:"status"`
	ProfileID       int64      `json:"profile_id"`
	ProfileCode     string     `json:"profile_code"`
	RequesterUserID int64      `json:"requester_user_id"`
	RequesterName   *string    `json:"requester_name"`
	RequesterPhone  *string    `json:"requester_phone"`
	OwnerUserID     int64      `json:"owner_user_id"`
	OwnerName       *string    `json:"owner_name"`
	OwnerPhone      *string    `json:"owner_phone"`
	MessageCount    int        `json:"message_count"`
	LastMessage     *string    `json:"last_message"`
	LastMessageAt   *time.Time `json:"last_message_at"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

// ListAllThreads returns every marriage chat thread for the admin oversight page.
func (s *Store) ListAllThreads(ctx context.Context, q string) ([]AdminThreadView, error) {
	args := []any{}
	where := "WHERE 1=1"
	if t := strings.TrimSpace(q); t != "" {
		args = append(args, "%"+t+"%")
		where += ` AND (rp.full_name ILIKE $1 OR op.full_name ILIKE $1 OR mp.profile_code ILIKE $1)`
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id, t.status, t.profile_id, mp.profile_code,
		       t.requester_user_id, rp.full_name, ru.phone,
		       t.owner_user_id, op.full_name, ou.phone,
		       COALESCE((SELECT COUNT(*) FROM marriage_chat_messages m WHERE m.thread_id = t.id), 0),
		       lm.body, lm.created_at,
		       t.created_at, t.updated_at
		  FROM marriage_chat_threads t
		  JOIN marriage_profiles mp ON mp.id = t.profile_id
		  LEFT JOIN users ru ON ru.id = t.requester_user_id
		  LEFT JOIN user_profiles rp ON rp.user_id = t.requester_user_id
		  LEFT JOIN users ou ON ou.id = t.owner_user_id
		  LEFT JOIN user_profiles op ON op.user_id = t.owner_user_id
		  LEFT JOIN LATERAL (
		     SELECT body, created_at FROM marriage_chat_messages m
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
		if err := rows.Scan(&v.ID, &v.Status, &v.ProfileID, &v.ProfileCode,
			&v.RequesterUserID, &v.RequesterName, &v.RequesterPhone,
			&v.OwnerUserID, &v.OwnerName, &v.OwnerPhone,
			&v.MessageCount, &v.LastMessage, &v.LastMessageAt,
			&v.CreatedAt, &v.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// AdminMessage is one message with the real sender identity, for staff oversight.
type AdminMessage struct {
	ID           int64     `json:"id"`
	ThreadID     int64     `json:"thread_id"`
	SenderUserID int64     `json:"sender_user_id"`
	SenderRole   string    `json:"sender_role"`
	SenderName   *string   `json:"sender_name"`
	Body         string    `json:"body"`
	CreatedAt    time.Time `json:"created_at"`
}

func (s *Store) AdminListMessages(ctx context.Context, threadID int64) ([]AdminMessage, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT m.id, m.thread_id, m.sender_user_id, m.sender_role, p.full_name, m.body, m.created_at
		  FROM marriage_chat_messages m
		  LEFT JOIN user_profiles p ON p.user_id = m.sender_user_id
		 WHERE m.thread_id = $1
		 ORDER BY m.id ASC`,
		threadID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []AdminMessage{}
	for rows.Next() {
		var m AdminMessage
		if err := rows.Scan(&m.ID, &m.ThreadID, &m.SenderUserID, &m.SenderRole, &m.SenderName, &m.Body, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
