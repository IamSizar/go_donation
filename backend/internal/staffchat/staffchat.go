// Package staffchat implements Note #36's "Operational Administrative
// Chats" — direct messaging between any two dashboard (staff_tier != 'user')
// accounts, e.g. Manager ↔ Staff Member. Unlike the donor↔beneficiary chat
// there is no accept/decline step: both parties are already trusted staff,
// so a thread is simply created and immediately usable on the first message.
// One thread per unordered pair — canonically stored with the lower user id
// first (user_a_id < user_b_id), so a lookup from either direction finds it.
package staffchat

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
	ErrNotFound = errors.New("thread not found")
	ErrNotParty = errors.New("you are not a participant in this chat")
	ErrSelf     = errors.New("you cannot message yourself")
)

type Thread struct {
	ID        int64     `json:"id"`
	UserAID   int64     `json:"user_a_id"`
	UserBID   int64     `json:"user_b_id"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (t Thread) IsParticipant(userID int64) bool {
	return userID == t.UserAID || userID == t.UserBID
}

func (t Thread) OtherUserID(senderID int64) int64 {
	if t.UserAID == senderID {
		return t.UserBID
	}
	return t.UserAID
}

// GetOrCreateThread returns the existing thread for this staff pair, or
// creates one. userA/userB order doesn't matter — canonicalized internally.
func (s *Store) GetOrCreateThread(ctx context.Context, userA, userB int64) (Thread, error) {
	if userA == userB {
		return Thread{}, ErrSelf
	}
	lo, hi := userA, userB
	if lo > hi {
		lo, hi = hi, lo
	}
	var t Thread
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO staff_chat_threads (user_a_id, user_b_id)
		VALUES ($1, $2)
		ON CONFLICT (user_a_id, user_b_id) DO UPDATE SET user_a_id = EXCLUDED.user_a_id
		RETURNING id, user_a_id, user_b_id, created_at, updated_at`,
		lo, hi,
	).Scan(&t.ID, &t.UserAID, &t.UserBID, &t.CreatedAt, &t.UpdatedAt)
	return t, err
}

func (s *Store) GetThread(ctx context.Context, threadID int64) (Thread, error) {
	var t Thread
	err := s.Pool.QueryRow(ctx, `
		SELECT id, user_a_id, user_b_id, created_at, updated_at
		  FROM staff_chat_threads WHERE id = $1`,
		threadID,
	).Scan(&t.ID, &t.UserAID, &t.UserBID, &t.CreatedAt, &t.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return t, ErrNotFound
	}
	return t, err
}

// ThreadView is a thread enriched for one viewing user.
type ThreadView struct {
	ID            int64      `json:"id"`
	OtherUserID   int64      `json:"other_user_id"`
	OtherName     *string    `json:"other_name"`
	OtherTier     *string    `json:"other_staff_tier"`
	LastMessage   *string    `json:"last_message"`
	LastMessageAt *time.Time `json:"last_message_at"`
	UnreadCount   int        `json:"unread_count"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

func (s *Store) ListThreadsForUser(ctx context.Context, userID int64) ([]ThreadView, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id,
		       CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END AS other_id,
		       op.full_name, ou.staff_tier,
		       lm.body, lm.created_at,
		       COALESCE((
		         SELECT COUNT(*) FROM staff_chat_messages m
		          WHERE m.thread_id = t.id
		            AND m.sender_user_id <> $1
		            AND m.id > COALESCE((SELECT last_read_msg_id FROM staff_chat_reads r
		                                  WHERE r.thread_id = t.id AND r.user_id = $1), 0)
		       ), 0) AS unread,
		       t.updated_at
		  FROM staff_chat_threads t
		  LEFT JOIN users ou ON ou.id = (CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END)
		  LEFT JOIN user_profiles op ON op.user_id = (CASE WHEN t.user_a_id = $1 THEN t.user_b_id ELSE t.user_a_id END)
		  LEFT JOIN LATERAL (
		      SELECT body, created_at FROM staff_chat_messages m
		       WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1
		  ) lm ON TRUE
		 WHERE (t.user_a_id = $1 OR t.user_b_id = $1)
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
		if err := rows.Scan(&v.ID, &v.OtherUserID, &v.OtherName, &v.OtherTier,
			&v.LastMessage, &v.LastMessageAt, &v.UnreadCount, &v.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

type Message struct {
	ID           int64     `json:"id"`
	ThreadID     int64     `json:"thread_id"`
	SenderUserID int64     `json:"sender_user_id"`
	SenderName   *string   `json:"sender_name"`
	Body         string    `json:"body"`
	CreatedAt    time.Time `json:"created_at"`
}

func (s *Store) ListMessages(ctx context.Context, threadID int64) ([]Message, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT m.id, m.thread_id, m.sender_user_id, p.full_name, m.body, m.created_at
		  FROM staff_chat_messages m
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
		if err := rows.Scan(&m.ID, &m.ThreadID, &m.SenderUserID, &m.SenderName, &m.Body, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) PostMessage(ctx context.Context, threadID, senderID int64, body string) (Message, error) {
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
		INSERT INTO staff_chat_messages (thread_id, sender_user_id, body)
		VALUES ($1, $2, $3)
		RETURNING id, thread_id, sender_user_id, body, created_at`,
		threadID, senderID, body,
	).Scan(&m.ID, &m.ThreadID, &m.SenderUserID, &m.Body, &m.CreatedAt); err != nil {
		return m, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE staff_chat_threads SET updated_at = CURRENT_TIMESTAMP WHERE id = $1`, threadID); err != nil {
		return m, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO staff_chat_reads (thread_id, user_id, last_read_msg_id) VALUES ($1, $2, $3)
		ON CONFLICT (thread_id, user_id) DO UPDATE SET last_read_msg_id = GREATEST(staff_chat_reads.last_read_msg_id, EXCLUDED.last_read_msg_id)`,
		threadID, senderID, m.ID); err != nil {
		return m, err
	}
	if err := tx.Commit(ctx); err != nil {
		return m, err
	}
	return m, nil
}

func (s *Store) MarkRead(ctx context.Context, threadID, userID int64) error {
	_, err := s.Pool.Exec(ctx, `
		INSERT INTO staff_chat_reads (thread_id, user_id, last_read_msg_id)
		VALUES ($1, $2, COALESCE((SELECT MAX(id) FROM staff_chat_messages WHERE thread_id = $1), 0))
		ON CONFLICT (thread_id, user_id)
		DO UPDATE SET last_read_msg_id = COALESCE((SELECT MAX(id) FROM staff_chat_messages WHERE thread_id = $1), 0)`,
		threadID, userID)
	return err
}

// Directory entry — one dashboard account, for the "start a new chat" picker.
type DirectoryEntry struct {
	UserID    int64   `json:"user_id"`
	FullName  *string `json:"full_name"`
	Phone     string  `json:"phone"`
	StaffTier string  `json:"staff_tier"`
}

// Directory lists every dashboard (staff_tier != 'user') account except the caller.
func (s *Store) Directory(ctx context.Context, excludeUserID int64) ([]DirectoryEntry, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT u.id, p.full_name, u.phone, u.staff_tier
		  FROM users u
		  LEFT JOIN user_profiles p ON p.user_id = u.id
		 WHERE u.staff_tier <> 'user' AND u.id <> $1
		 ORDER BY u.staff_tier, p.full_name NULLS LAST`,
		excludeUserID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []DirectoryEntry{}
	for rows.Next() {
		var d DirectoryEntry
		if err := rows.Scan(&d.UserID, &d.FullName, &d.Phone, &d.StaffTier); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}
