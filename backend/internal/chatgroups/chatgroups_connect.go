// Connect-request flow: a donor/beneficiary/volunteer asks staff to open a
// chat, staff approves or declines. Approval creates the chat_group_threads
// group AND stamps the request approved in ONE transaction, reusing the same
// insertMembers helper CreateGroup uses (chatgroups.go) — there is never an
// "approved, no group yet" dangling state. See chat_group_connect_requests in
// the migration for the full column list and constraints this file relies on.
package chatgroups

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

// ConnectRequestStatus is a chat_group_connect_requests.status value.
type ConnectRequestStatus string

const (
	RequestPending  ConnectRequestStatus = "pending"
	RequestApproved ConnectRequestStatus = "approved"
	RequestDeclined ConnectRequestStatus = "declined"
)

// ConnectRequest mirrors one chat_group_connect_requests row, resolved for
// an admin inbox. Context resolution (turning context_id into a campaign
// title / case number / donation amount) belongs in the handler layer in a
// later phase — this type carries the raw ids, not a bare "context_id" the
// admin-web page would have to make sense of unassisted.
type ConnectRequest struct {
	ID             int64
	RequesterID    int64
	ContextType    string
	ContextID      int64
	TargetHint     *int64
	Message        string
	GroupID        *int64
	Status         ConnectRequestStatus
	DeclineReason  string
	DecidedByStaff *int64
	CreatedAt      string
}

// SubmitConnectRequest records a request. Resubmitting while one from the
// same user for the same context is still pending updates that row's
// message rather than creating a second one for staff to triage — enforced
// by the partial unique index in the migration.
func (s *Store) SubmitConnectRequest(ctx context.Context, requesterID int64, contextType string, contextID int64, targetHint *int64, message string) (int64, error) {
	if contextType != "donation" && contextType != "case" {
		return 0, errors.New("context_type must be 'donation' or 'case'")
	}
	message = strings.TrimSpace(message)
	if message == "" {
		return 0, errors.New("message must not be empty")
	}
	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO chat_group_connect_requests (requester_user_id, context_type, context_id, target_hint, message)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (requester_user_id, context_type, context_id) WHERE status = 'pending'
		DO UPDATE SET message = EXCLUDED.message
		RETURNING id`,
		requesterID, contextType, contextID, targetHint, message,
	).Scan(&id)
	return id, err
}

// ApproveConnectRequest creates the group AND stamps the request approved in
// ONE transaction — there is never an "approved, no group yet" state. Fails
// if the request is not currently pending.
func (s *Store) ApproveConnectRequest(ctx context.Context, requestID int64, kind Kind, memberTitle string, staffID int64, members []MemberInput) (int64, error) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var status string
	if err := tx.QueryRow(ctx,
		`SELECT status FROM chat_group_connect_requests WHERE id = $1 FOR UPDATE`, requestID,
	).Scan(&status); err != nil {
		return 0, err
	}
	if status != string(RequestPending) {
		return 0, fmt.Errorf("request is %s, not pending", status)
	}

	title := memberTitle
	if kind == KindMasked {
		title = ""
	}
	var groupID int64
	if err := tx.QueryRow(ctx,
		`INSERT INTO chat_group_threads (kind, member_title, created_by_staff_id)
		 VALUES ($1, $2, $3) RETURNING id`,
		string(kind), title, staffID,
	).Scan(&groupID); err != nil {
		return 0, err
	}
	if err := insertMembers(ctx, tx, groupID, kind, staffID, members); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE chat_group_connect_requests
		    SET status = 'approved', group_id = $2, decided_by_staff_id = $3, decided_at = now()
		  WHERE id = $1`,
		requestID, groupID, staffID,
	); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return groupID, nil
}

// DeclineConnectRequest marks a request declined with a reason, shown back
// to the requester. Fails if the request is not currently pending.
func (s *Store) DeclineConnectRequest(ctx context.Context, requestID, staffID int64, reason string) error {
	reason = strings.TrimSpace(reason)
	if reason == "" {
		return errors.New("decline_reason must not be empty")
	}
	ct, err := s.Pool.Exec(ctx, `
		UPDATE chat_group_connect_requests
		   SET status = 'declined', decline_reason = $3, decided_by_staff_id = $2, decided_at = now()
		 WHERE id = $1 AND status = 'pending'`,
		requestID, staffID, reason,
	)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return errors.New("request not found or already decided")
	}
	return nil
}

// ListConnectRequests lists requests, optionally filtered by status ("" for
// all statuses).
func (s *Store) ListConnectRequests(ctx context.Context, status string) ([]ConnectRequest, error) {
	query := `
		SELECT id, requester_user_id, context_type, context_id, target_hint,
		       message, group_id, status, decline_reason, decided_by_staff_id, created_at::text
		  FROM chat_group_connect_requests`
	args := []any{}
	if status != "" {
		query += ` WHERE status = $1`
		args = append(args, status)
	}
	query += ` ORDER BY created_at DESC`

	rows, err := s.Pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []ConnectRequest{}
	for rows.Next() {
		var r ConnectRequest
		if err := rows.Scan(&r.ID, &r.RequesterID, &r.ContextType, &r.ContextID, &r.TargetHint,
			&r.Message, &r.GroupID, &r.Status, &r.DeclineReason, &r.DecidedByStaff, &r.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
