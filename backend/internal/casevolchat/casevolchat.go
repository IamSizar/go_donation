// Package casevolchat implements Note #36's Staff↔Volunteer↔Beneficiary
// chat: once a volunteer's mission signup is linked to a beneficiary case
// (migration 060) AND that signup reaches "approved" or further along the
// lifecycle, a 3-way thread opens between the volunteer, the case's
// beneficiary, and staff — any admin may relay as "Support," or claim the
// thread to become the named "Responsible Staff Member" (same claim pattern
// migration 059 added to the donor↔beneficiary chat).
//
// Unlike the marriage chat (internal/marriagechat), identities are NOT
// masked — this is operational coordination, not a sensitive introduction,
// so the volunteer and beneficiary see each other's real names.
package casevolchat

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/privacy"
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

const (
	RoleVolunteer   = "volunteer"
	RoleBeneficiary = "beneficiary"
	RoleStaff       = "staff"
)

var (
	ErrNotFound       = errors.New("thread not found")
	ErrNotParty       = errors.New("you are not a participant in this chat")
	ErrAlreadyClaimed = errors.New("this chat is already claimed by another staff member")
)

// EnsureThreadForSignup opens a thread for a signup if one doesn't already
// exist, PROVIDED the signup is actually eligible: linked to a case whose
// owner has a real user account, and the signup's status is one of
// approved/joined/completion_requested/completed. Called after any action
// that could make a signup newly eligible (assigning a case, or changing
// signup status) — a no-op (returns nil, nil) when not yet eligible, so
// callers can fire-and-forget this on every relevant write.
func (s *Store) EnsureThreadForSignup(ctx context.Context, signupID int64) (*int64, error) {
	var volunteerID, caseID int64
	var beneficiaryID *int64
	var status string
	err := s.Pool.QueryRow(ctx, `
		SELECT sg.user_id, sg.beneficiary_case_id, sg.status, bc.user_id
		  FROM volunteer_mission_signups sg
		  JOIN beneficiary_cases bc ON bc.id = sg.beneficiary_case_id
		 WHERE sg.id = $1`,
		signupID,
	).Scan(&volunteerID, &caseID, &status, &beneficiaryID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil // no case linked yet
	}
	if err != nil {
		return nil, err
	}
	if beneficiaryID == nil {
		return nil, nil // case has no linked app-user account to chat with
	}
	switch status {
	case "approved", "joined", "completion_requested", "completed":
	default:
		return nil, nil // not eligible yet (still pending, or a terminal failure)
	}

	var threadID int64
	err = s.Pool.QueryRow(ctx, `
		INSERT INTO case_volunteer_chat_threads (signup_id, case_id, volunteer_user_id, beneficiary_user_id)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (signup_id) DO UPDATE SET signup_id = EXCLUDED.signup_id
		RETURNING id`,
		signupID, caseID, volunteerID, *beneficiaryID,
	).Scan(&threadID)
	if err != nil {
		return nil, err
	}
	return &threadID, nil
}

type Thread struct {
	ID                  int64     `json:"id"`
	SignupID            int64     `json:"signup_id"`
	CaseID              int64     `json:"case_id"`
	VolunteerUserID     int64     `json:"volunteer_user_id"`
	BeneficiaryUserID   int64     `json:"beneficiary_user_id"`
	AssignedStaffUserID *int64    `json:"assigned_staff_user_id"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

func (t Thread) IsParticipant(userID int64) bool {
	return userID == t.VolunteerUserID || userID == t.BeneficiaryUserID
}

func (t Thread) RoleFor(userID int64) string {
	if userID == t.VolunteerUserID {
		return RoleVolunteer
	}
	return RoleBeneficiary
}

func (t Thread) CounterpartIDs(senderID int64) []int64 {
	out := []int64{}
	if t.VolunteerUserID != senderID {
		out = append(out, t.VolunteerUserID)
	}
	if t.BeneficiaryUserID != senderID {
		out = append(out, t.BeneficiaryUserID)
	}
	return out
}

// MessageCountForSignup reports how many chat messages hang off a signup, via
// its thread. It returns 0 when the signup has no thread at all, and 0 when
// the thread exists but nobody has spoken in it.
//
// It exists for the admin delete guard. volunteer_mission_signups cascades to
// case_volunteer_chat_threads (migration 061), which cascades on to its
// messages and reads — and handlers.trashRow archives only the row it deletes,
// so a delete would take the conversation with it and المهملات would hand back
// the signup alone. The caller uses this to refuse rather than destroy.
//
// WHY MESSAGES AND NOT THE THREAD. EnsureThreadForSignup opens a thread
// automatically the moment a signup with a linked case is approved, before
// anyone has typed anything. Refusing on the mere existence of a thread would
// have made nearly every approved signup permanently undeletable. An empty
// thread holds no conversation and re-opens by itself, so it is not worth
// blocking an operator over; a single message is.
func (s *Store) MessageCountForSignup(ctx context.Context, signupID int64) (int, error) {
	if signupID <= 0 {
		return 0, errors.New("signupID is required")
	}
	var n int
	if err := s.Pool.QueryRow(ctx, `
		SELECT COUNT(m.id)
		  FROM case_volunteer_chat_threads t
		  JOIN case_volunteer_chat_messages m ON m.thread_id = t.id
		 WHERE t.signup_id = $1`, signupID,
	).Scan(&n); err != nil {
		return 0, fmt.Errorf("count chat messages for signup %d: %w", signupID, err)
	}
	return n, nil
}

func (s *Store) GetThread(ctx context.Context, threadID int64) (Thread, error) {
	var t Thread
	err := s.Pool.QueryRow(ctx, `
		SELECT id, signup_id, case_id, volunteer_user_id, beneficiary_user_id, assigned_staff_user_id, created_at, updated_at
		  FROM case_volunteer_chat_threads WHERE id = $1`,
		threadID,
	).Scan(&t.ID, &t.SignupID, &t.CaseID, &t.VolunteerUserID, &t.BeneficiaryUserID, &t.AssignedStaffUserID, &t.CreatedAt, &t.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return t, ErrNotFound
	}
	return t, err
}

func (s *Store) ClaimThread(ctx context.Context, threadID, staffUserID int64) (Thread, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, err
	}
	if t.AssignedStaffUserID != nil && *t.AssignedStaffUserID != staffUserID {
		return t, ErrAlreadyClaimed
	}
	if _, err := s.Pool.Exec(ctx,
		`UPDATE case_volunteer_chat_threads SET assigned_staff_user_id = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
		threadID, staffUserID); err != nil {
		return t, err
	}
	t.AssignedStaffUserID = &staffUserID
	return t, nil
}

func (s *Store) ReleaseThread(ctx context.Context, threadID int64) (Thread, error) {
	t, err := s.GetThread(ctx, threadID)
	if err != nil {
		return t, err
	}
	if _, err := s.Pool.Exec(ctx,
		`UPDATE case_volunteer_chat_threads SET assigned_staff_user_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
		threadID); err != nil {
		return t, err
	}
	t.AssignedStaffUserID = nil
	return t, nil
}

// ThreadView is a thread enriched for one viewing (non-staff) user — real
// identities, unlike the marriage chat.
// All four title columns, not just the English one.
//
// beneficiary_cases keeps a title per language and the dashboard has an
// operator working entirely in Arabic; selecting `public_title` alone meant
// the case picker and the thread header listed cases in English while the
// Arabic title sat unread in the same row. The SPA picks the reader's
// language (lib/localizedContent.ts) and falls back through Arabic to
// English, so a case titled in only one language still identifies itself.
type ThreadView struct {
	ID                int64      `json:"id"`
	MyRole            string     `json:"my_role"` // "volunteer" | "beneficiary"
	CaseID            int64      `json:"case_id"`
	CaseCode          string     `json:"case_code"`
	CaseTitle         string     `json:"case_title"`
	CaseTitleAr       *string    `json:"public_title_ar"`
	CaseTitleSorani   *string    `json:"public_title_sorani"`
	CaseTitleBadini   *string    `json:"public_title_badini"`
	OtherUserID       int64      `json:"other_user_id"`
	OtherName         *string    `json:"other_name"`
	AssignedStaffName *string    `json:"assigned_staff_name"`
	LastMessage       *string    `json:"last_message"`
	LastMessageAt     *time.Time `json:"last_message_at"`
	UnreadCount       int        `json:"unread_count"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

func (s *Store) ListThreadsForUser(ctx context.Context, userID int64) ([]ThreadView, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id,
		       CASE WHEN t.volunteer_user_id = $1 THEN 'volunteer' ELSE 'beneficiary' END AS my_role,
		       t.case_id, bc.case_code, bc.public_title,
		       bc.public_title_ar, bc.public_title_sorani, bc.public_title_badini,
		       CASE WHEN t.volunteer_user_id = $1 THEN t.beneficiary_user_id ELSE t.volunteer_user_id END AS other_id,
		       op.full_name,
		       sp.full_name AS assigned_staff_name,
		       lm.body, lm.created_at,
		       COALESCE((
		         SELECT COUNT(*) FROM case_volunteer_chat_messages m
		          WHERE m.thread_id = t.id
		            AND m.sender_user_id <> $1
		            AND m.id > COALESCE((SELECT last_read_msg_id FROM case_volunteer_chat_reads r
		                                  WHERE r.thread_id = t.id AND r.user_id = $1), 0)
		       ), 0) AS unread,
		       t.updated_at
		  FROM case_volunteer_chat_threads t
		  JOIN beneficiary_cases bc ON bc.id = t.case_id
		  LEFT JOIN user_profiles op ON op.user_id = (CASE WHEN t.volunteer_user_id = $1 THEN t.beneficiary_user_id ELSE t.volunteer_user_id END)
		  LEFT JOIN user_profiles sp ON sp.user_id = t.assigned_staff_user_id
		  LEFT JOIN LATERAL (
		      SELECT body, created_at FROM case_volunteer_chat_messages m
		       WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1
		  ) lm ON TRUE
		 WHERE (t.volunteer_user_id = $1 OR t.beneficiary_user_id = $1)
		   -- Migration 117: ARCHIVE is a staff moderation action that HIDES
		   -- the thread from its participants; staff keep seeing it.
		   AND t.archived_at IS NULL
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
		if err := rows.Scan(&v.ID, &v.MyRole, &v.CaseID, &v.CaseCode, &v.CaseTitle,
			&v.CaseTitleAr, &v.CaseTitleSorani, &v.CaseTitleBadini,
			&v.OtherUserID, &v.OtherName, &v.AssignedStaffName,
			&v.LastMessage, &v.LastMessageAt, &v.UnreadCount, &v.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// K8 — the counterpart's name belongs to them, so their Privacy Settings
	// decide whether it is served. (This thread carries no phone number; the
	// package note above is about staff identity masking, which is a separate
	// concern.)
	others := make([]int64, 0, len(out))
	for _, v := range out {
		others = append(others, v.OtherUserID)
	}
	seen, err := privacy.LoadFor(ctx, s.Pool, userID, others)
	if err != nil {
		// Fail CLOSED: empty settings hide nothing.
		return nil, fmt.Errorf("case-volunteer thread privacy: %w", err)
	}
	for i := range out {
		out[i].OtherName = seen.Name(out[i].OtherUserID, out[i].OtherName)
	}
	return out, nil
}

type Message struct {
	ID           int64     `json:"id"`
	ThreadID     int64     `json:"thread_id"`
	SenderUserID int64     `json:"sender_user_id"`
	SenderRole   string    `json:"sender_role"`
	SenderName   *string   `json:"sender_name"`
	Body         string    `json:"body"`
	CreatedAt    time.Time `json:"created_at"`
}

// ListMessagesForViewer is the message list served to an APP USER (K8): each
// sender's name passes through their own Privacy Settings. ListMessages stays
// raw for the admin path (AdminListMessages reads it), where staff visibility
// is governed by the separate sensitive_data permission.
func (s *Store) ListMessagesForViewer(ctx context.Context, threadID, viewerID int64) ([]Message, error) {
	msgs, err := s.ListMessages(ctx, threadID)
	if err != nil {
		return nil, err
	}
	senders := make([]int64, 0, len(msgs))
	for _, m := range msgs {
		senders = append(senders, m.SenderUserID)
	}
	seen, err := privacy.LoadFor(ctx, s.Pool, viewerID, senders)
	if err != nil {
		return nil, fmt.Errorf("case-volunteer message privacy: %w", err)
	}
	for i := range msgs {
		msgs[i].SenderName = seen.Name(msgs[i].SenderUserID, msgs[i].SenderName)
	}
	return msgs, nil
}

func (s *Store) ListMessages(ctx context.Context, threadID int64) ([]Message, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT m.id, m.thread_id, m.sender_user_id, m.sender_role, p.full_name, m.body, m.created_at
		  FROM case_volunteer_chat_messages m
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

func (s *Store) PostMessage(ctx context.Context, threadID, senderID int64, role, body string) (Message, error) {
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
		INSERT INTO case_volunteer_chat_messages (thread_id, sender_user_id, sender_role, body)
		VALUES ($1, $2, $3, $4)
		RETURNING id, thread_id, sender_user_id, sender_role, body, created_at`,
		threadID, senderID, role, body,
	).Scan(&m.ID, &m.ThreadID, &m.SenderUserID, &m.SenderRole, &m.Body, &m.CreatedAt); err != nil {
		return m, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE case_volunteer_chat_threads SET updated_at = CURRENT_TIMESTAMP WHERE id = $1`, threadID); err != nil {
		return m, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO case_volunteer_chat_reads (thread_id, user_id, last_read_msg_id) VALUES ($1, $2, $3)
		ON CONFLICT (thread_id, user_id) DO UPDATE SET last_read_msg_id = GREATEST(case_volunteer_chat_reads.last_read_msg_id, EXCLUDED.last_read_msg_id)`,
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
		INSERT INTO case_volunteer_chat_reads (thread_id, user_id, last_read_msg_id)
		VALUES ($1, $2, COALESCE((SELECT MAX(id) FROM case_volunteer_chat_messages WHERE thread_id = $1), 0))
		ON CONFLICT (thread_id, user_id)
		DO UPDATE SET last_read_msg_id = COALESCE((SELECT MAX(id) FROM case_volunteer_chat_messages WHERE thread_id = $1), 0)`,
		threadID, userID)
	return err
}

// ===== Admin =====

type AdminThreadView struct {
	ID                  int64   `json:"id"`
	CaseID              int64   `json:"case_id"`
	CaseCode            string  `json:"case_code"`
	CaseTitle           string  `json:"case_title"`
	CaseTitleAr         *string `json:"public_title_ar"`
	CaseTitleSorani     *string `json:"public_title_sorani"`
	CaseTitleBadini     *string `json:"public_title_badini"`
	VolunteerUserID     int64   `json:"volunteer_user_id"`
	VolunteerName       *string `json:"volunteer_name"`
	VolunteerPhone      *string `json:"volunteer_phone"`
	BeneficiaryUserID   int64   `json:"beneficiary_user_id"`
	BeneficiaryName     *string `json:"beneficiary_name"`
	BeneficiaryPhone    *string `json:"beneficiary_phone"`
	AssignedStaffUserID *int64  `json:"assigned_staff_user_id"`
	AssignedStaffName   *string `json:"assigned_staff_name"`
	// Migration 117 — the staff-controlled lifecycle: open | paused | ended,
	// plus whether staff have archived it away from the participants.
	Lifecycle       string     `json:"lifecycle"`
	LifecycleReason *string    `json:"lifecycle_reason"`
	IsArchived      bool       `json:"is_archived"`
	MessageCount    int        `json:"message_count"`
	LastMessage     *string    `json:"last_message"`
	LastMessageAt   *time.Time `json:"last_message_at"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

func (s *Store) ListAllThreads(ctx context.Context, q string) ([]AdminThreadView, error) {
	args := []any{}
	where := "WHERE 1=1"
	if t := strings.TrimSpace(q); t != "" {
		args = append(args, "%"+t+"%")
		where += ` AND (vp.full_name ILIKE $1 OR bp.full_name ILIKE $1 OR bc.case_code ILIKE $1)`
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id, t.case_id, bc.case_code, bc.public_title,
		       bc.public_title_ar, bc.public_title_sorani, bc.public_title_badini,
		       t.volunteer_user_id, vp.full_name, vu.phone,
		       t.beneficiary_user_id, bp.full_name, bu.phone,
		       t.assigned_staff_user_id, sp.full_name,
		       t.lifecycle, t.lifecycle_reason, (t.archived_at IS NOT NULL),
		       COALESCE((SELECT COUNT(*) FROM case_volunteer_chat_messages m WHERE m.thread_id = t.id), 0),
		       lm.body, lm.created_at,
		       t.created_at, t.updated_at
		  FROM case_volunteer_chat_threads t
		  JOIN beneficiary_cases bc ON bc.id = t.case_id
		  LEFT JOIN users vu ON vu.id = t.volunteer_user_id
		  LEFT JOIN user_profiles vp ON vp.user_id = t.volunteer_user_id
		  LEFT JOIN users bu ON bu.id = t.beneficiary_user_id
		  LEFT JOIN user_profiles bp ON bp.user_id = t.beneficiary_user_id
		  LEFT JOIN user_profiles sp ON sp.user_id = t.assigned_staff_user_id
		  LEFT JOIN LATERAL (
		     SELECT body, created_at FROM case_volunteer_chat_messages m
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
		if err := rows.Scan(&v.ID, &v.CaseID, &v.CaseCode, &v.CaseTitle,
			&v.CaseTitleAr, &v.CaseTitleSorani, &v.CaseTitleBadini,
			&v.VolunteerUserID, &v.VolunteerName, &v.VolunteerPhone,
			&v.BeneficiaryUserID, &v.BeneficiaryName, &v.BeneficiaryPhone,
			&v.AssignedStaffUserID, &v.AssignedStaffName,
			&v.Lifecycle, &v.LifecycleReason, &v.IsArchived,
			&v.MessageCount, &v.LastMessage, &v.LastMessageAt,
			&v.CreatedAt, &v.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (s *Store) AdminListMessages(ctx context.Context, threadID int64) ([]Message, error) {
	return s.ListMessages(ctx, threadID)
}
