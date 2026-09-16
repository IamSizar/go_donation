package notify

import (
	"context"
	"errors"
	"slices"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Notification mirrors the JSON shape from the PHP GET /api/notifications.
type Notification struct {
	ID                   int64      `json:"id"`
	UserID               *int       `json:"user_id"`
	RoleID               *int       `json:"role_id"`
	Title                string     `json:"title"`
	TitleAr              *string    `json:"title_ar"`
	TitleSorani          *string    `json:"title_sorani"`
	TitleBadini          *string    `json:"title_badini"`
	Body                 string     `json:"body"`
	BodyAr               *string    `json:"body_ar"`
	BodySorani           *string    `json:"body_sorani"`
	BodyBadini           *string    `json:"body_badini"`
	NotificationType     *string    `json:"notification_type"`
	NotificationCategory string     `json:"notification_category"`
	Priority             int        `json:"priority"`
	ActionURL            *string    `json:"action_url"`
	RelatedEntityType    *string    `json:"related_entity_type"`
	RelatedEntityID      *int64     `json:"related_entity_id"`
	IsRead               int        `json:"is_read"`
	ReadAt               *time.Time `json:"read_at"`
	CreatedAt            time.Time  `json:"created_at"`
}

// ReadRetention is how long a READ notification stays in a user's list.
//
// The client's report was "old notifications must go away". Thirty days is
// long enough that a member can still find the confirmation of something they
// did last month, and short enough that the list is about now. It applies ONLY
// to rows the user has read: an unread notification is one they have never
// seen, and ageing it out would be losing it.
//
// It is a display rule, not a deletion: nothing removes the row, and raising
// this number brings the rows back.
const ReadRetention = 30 * 24 * time.Hour

// ListFilter narrows the notifications query.
type ListFilter struct {
	UserID     int64  // 0 = anonymous (only system-wide rows); a guest never gets chat-type rows
	RoleID     int    // 0 = don't filter
	Category   string // "" = all  | "normal","urgent","payment","campaign","system","reminder"
	Type       string // "" = all
	ReadStatus string // "all" (default) | "unread" | "read"
	Limit      int    // default 50
}

// ─── Guests and conversations (OPOS #26424) ─────────────────────────────

// chatNotificationTypes is every notification_type the backend writes about a
// conversation. A guest account never sees these rows. Guests must not read
// chats, and several of these rows carry the message itself as their body (an
// 80-character preview), so listing them would hand a guest the chat that
// auth.RequireNotGuest refuses on the chat routes.
//
// An explicit list rather than a LIKE 'chat%' prefix, so a type is hidden only
// because someone decided it is a conversation. chat_types_test.go builds
// every conversation template and fails if its type is missing here.
//
//   - chat_request, chat_accepted, chat_message: the donor ↔ campaign-owner
//     chat, and the support chat, whose staff replies are chat_message rows
//     from "Support" and cannot be told apart by type;
//   - chat_group_message: masked and team chat groups;
//   - marriage_chat_request, marriage_chat_accepted, marriage_chat_message:
//     the staff-mediated marriage chat;
//   - marriage_meeting_declined: the refusal of a request to open that chat.
//     Its approval arrives as marriage_chat_request, so both outcomes hide;
//   - staff_chat_message: the internal staff chat.
//
// Deliberately NOT here: support_request_submitted, support_ticket_replied and
// support_ticket_<status>. They belong to support TICKETS, which a guest may
// still read at GET /api/support/mine, and they never quote the reply.
var chatNotificationTypes = []string{
	"chat_request",
	"chat_accepted",
	"chat_message",
	"chat_group_message",
	"marriage_chat_request",
	"marriage_chat_accepted",
	"marriage_chat_message",
	"marriage_meeting_declined",
	"staff_chat_message",
}

// isConversationType reports whether a notification_type describes a message in
// a conversation, rather than an event about a record.
//
// Send uses it to exempt these types from the duplicate check (OPOS #26481):
// their wording repeats by design — the marriage-chat template is one fixed
// sentence, and a chat group's body is the message preview — so a text-based
// dedupe reads every message after the first as a duplicate and silences the
// chat. Each of these is sent once per row already inserted into its own
// messages table, so a repeat is a real second message.
//
// The same list as the guest filter on purpose: "is this a conversation?" has
// one answer in this package, and a new chat template added to that list is
// exempted here without anybody having to remember a second place.
func isConversationType(notificationType string) bool {
	return slices.Contains(chatNotificationTypes, notificationType)
}

// ChatNotificationTypes returns a copy of the chat-type list, so a caller can
// bind it as a query argument without being able to edit the shared list.
func ChatNotificationTypes() []string {
	return slices.Clone(chatNotificationTypes)
}

// GuestChatExclusionSQL returns a WHERE predicate that drops chat-type rows
// when the user is a guest and keeps every row otherwise. It expects
// app_notifications aliased as n. userIDArg and typesArg are placeholders such
// as "$2", never values: the caller binds the user id and
// ChatNotificationTypes() to them.
//
// The filter lives in SQL, not in Go after the fetch, so LIMIT and the unread
// filter only ever count rows the caller may see. Guest status comes from
// users.is_guest, the column the token resolver reads on every request, so an
// upgraded account sees its chat notifications again straight away.
//
// COALESCE keeps an untyped row (notification_type NULL) visible. Without it,
// "NULL = ANY(...)" is NULL, and NOT NULL would drop that row for a guest.
func GuestChatExclusionSQL(userIDArg, typesArg string) string {
	return `NOT (COALESCE(n.notification_type, '') = ANY(` + typesArg + `::text[])
	         AND EXISTS (SELECT 1 FROM users guest_u
	                      WHERE guest_u.id = ` + userIDArg + ` AND guest_u.is_guest))`
}

// List returns notifications visible to the user, with effective read status
// computed against app_notification_reads for broadcast rows (user_id IS NULL).
//
// A guest account's list leaves out chat-type rows (GuestChatExclusionSQL).
// The unread filter is the same query, so a guest's unread count excludes them
// too. Every other caller and every other type is unaffected.
func (n *Notifier) List(ctx context.Context, f ListFilter) ([]Notification, error) {
	limit := f.Limit
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	switch strings.ToLower(strings.TrimSpace(f.ReadStatus)) {
	case "unread":
		f.ReadStatus = "unread"
	case "read":
		f.ReadStatus = "read"
	default:
		f.ReadStatus = "all"
	}

	// category and effective-read SQL fragments.
	categorySQL := `
	  CASE
	    WHEN n.notification_category IS NOT NULL
	         AND n.notification_category <> ''
	         AND n.notification_category <> 'normal'
	      THEN n.notification_category
	    WHEN n.notification_type LIKE '%urgent%'
	         OR n.notification_type LIKE '%support%'
	         OR n.notification_type LIKE '%case%'
	      THEN 'urgent'
	    WHEN n.notification_type LIKE '%payment%'
	         OR n.notification_type LIKE '%donation%'
	         OR n.notification_type LIKE '%sponsorship%'
	      THEN 'payment'
	    WHEN n.notification_type LIKE '%campaign%'
	         OR n.notification_type LIKE '%project%'
	         OR n.notification_type IN ('media_post', 'news', 'activity')
	      THEN 'campaign'
	    WHEN n.notification_type LIKE '%reminder%'
	         OR n.notification_type LIKE '%due%'
	      THEN 'reminder'
	    WHEN n.notification_type LIKE '%system%'
	         OR n.notification_type LIKE '%admin%'
	      THEN 'system'
	    ELSE 'normal'
	  END`

	var effectiveReadSQL, effectiveReadAtSQL string
	args := []any{}
	argi := 0
	nextArg := func(v any) string {
		args = append(args, v)
		argi++
		return "$" + itoa(argi)
	}

	if f.UserID > 0 {
		uidArg := nextArg(f.UserID)
		effectiveReadSQL = `
		  CASE
		    WHEN n.user_id IS NULL THEN
		      CASE WHEN EXISTS (
		        SELECT 1 FROM app_notification_reads r
		         WHERE r.notification_id = n.id AND r.user_id = ` + uidArg + `
		      ) THEN 1 ELSE 0 END
		    ELSE n.is_read
		  END`
		effectiveReadAtSQL = `
		  CASE
		    WHEN n.user_id IS NULL THEN (
		      SELECT r.read_at FROM app_notification_reads r
		       WHERE r.notification_id = n.id AND r.user_id = ` + uidArg + `
		       LIMIT 1
		    )
		    ELSE n.read_at
		  END`
	} else {
		effectiveReadSQL = "n.is_read"
		effectiveReadAtSQL = "n.read_at"
	}

	where := []string{"1=1"}
	// Cleared rows are gone from every list, whoever asked and whatever the
	// filters say. A row the user owns carries its own stamp; a broadcast row
	// carries the user's stamp on their app_notification_reads row, so one
	// user clearing an announcement leaves everyone else's list alone.
	where = append(where, "n.cleared_at IS NULL")
	if f.UserID > 0 {
		clearUserArg := nextArg(f.UserID)
		where = append(where, `NOT EXISTS (
		    SELECT 1 FROM app_notification_reads rc
		     WHERE rc.notification_id = n.id
		       AND rc.user_id = `+clearUserArg+`
		       AND rc.cleared_at IS NOT NULL)`)
	}
	// Retention. A READ notification older than ReadRetention drops out on its
	// own: the client asked that old notifications go away, and a row the user
	// has already read is the one kind it is safe to retire without asking.
	// UNREAD rows never age out at any age — the user has not seen them, and
	// hiding one would be losing it. Nothing is deleted; this is what the list
	// selects.
	where = append(where, "NOT (("+effectiveReadSQL+") = 1 AND n.created_at < NOW() - INTERVAL '"+
		itoa(int(ReadRetention.Hours()))+" hours')")
	if f.UserID > 0 {
		uidArg := nextArg(f.UserID)
		where = append(where, "(n.user_id = "+uidArg+" OR n.user_id IS NULL)")
		// OPOS #26424 — a guest never sees chat-type rows. The user id gets a
		// fresh placeholder so each one takes its type from a single column.
		guestUserArg := nextArg(f.UserID)
		chatTypesArg := nextArg(chatNotificationTypes)
		where = append(where, GuestChatExclusionSQL(guestUserArg, chatTypesArg))
	} else {
		where = append(where, "n.user_id IS NULL")
	}
	if f.RoleID > 0 {
		roleArg := nextArg(f.RoleID)
		where = append(where, "(n.role_id = "+roleArg+" OR n.role_id IS NULL)")
	}
	cat := strings.ToLower(strings.TrimSpace(f.Category))
	switch cat {
	case "normal", "urgent", "payment", "campaign", "system", "reminder":
		where = append(where, "("+categorySQL+") = "+nextArg(cat))
	}
	if t := strings.TrimSpace(f.Type); t != "" {
		where = append(where, "n.notification_type = "+nextArg(t))
	}
	switch f.ReadStatus {
	case "unread":
		where = append(where, "("+effectiveReadSQL+") = 0")
	case "read":
		where = append(where, "("+effectiveReadSQL+") = 1")
	}

	q := `
	SELECT n.id, n.user_id, n.role_id,
	       n.title, n.title_ar, NULL::text, NULL::text,
	       n.body,  n.body_ar,  NULL::text, NULL::text,
	       n.notification_type,
	       ` + categorySQL + ` AS notification_category,
	       n.priority,
	       n.action_url, n.related_entity_type, n.related_entity_id,
	       (` + effectiveReadSQL + `)::int AS is_read,
	       (` + effectiveReadAtSQL + `)    AS read_at,
	       n.created_at
	  FROM app_notifications n
	 WHERE ` + strings.Join(where, " AND ") + `
	 ORDER BY
	   CASE WHEN (` + effectiveReadSQL + `) = 0
	             AND (` + categorySQL + `) IN ('urgent','payment')
	        THEN 0 ELSE 1 END ASC,
	   CASE (` + categorySQL + `)
	     WHEN 'urgent'   THEN 600
	     WHEN 'payment'  THEN 500
	     WHEN 'campaign' THEN 400
	     WHEN 'system'   THEN 300
	     WHEN 'reminder' THEN 200
	     ELSE 100
	   END + n.priority DESC,
	   n.created_at DESC,
	   n.id DESC
	 LIMIT ` + itoa(limit)

	rows, err := n.Pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []Notification{}
	for rows.Next() {
		var x Notification
		err := rows.Scan(
			&x.ID, &x.UserID, &x.RoleID,
			&x.Title, &x.TitleAr, &x.TitleSorani, &x.TitleBadini,
			&x.Body, &x.BodyAr, &x.BodySorani, &x.BodyBadini,
			&x.NotificationType,
			&x.NotificationCategory,
			&x.Priority,
			&x.ActionURL, &x.RelatedEntityType, &x.RelatedEntityID,
			&x.IsRead, &x.ReadAt, &x.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

// MarkResult is the outcome enum for MarkRead.
type MarkResult int

const (
	MarkOK MarkResult = iota
	MarkNotFound
)

// MarkRead marks one notification as read for the user.
//   - If the notification's user_id == userID, set is_read=1, read_at=NOW().
//   - Otherwise (broadcast row, user_id IS NULL), upsert into app_notification_reads.
//
// Returns MarkNotFound if the row doesn't exist or isn't visible to the user.
func (n *Notifier) MarkRead(ctx context.Context, notificationID, userID int64) (MarkResult, error) {
	if notificationID <= 0 || userID <= 0 {
		return MarkNotFound, errors.New("invalid args")
	}
	var ownerID *int64
	err := n.Pool.QueryRow(ctx,
		`SELECT user_id FROM app_notifications
		  WHERE id = $1 AND (user_id = $2 OR user_id IS NULL)
		  LIMIT 1`,
		notificationID, userID,
	).Scan(&ownerID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return MarkNotFound, nil
		}
		return MarkNotFound, err
	}

	if ownerID != nil && *ownerID == userID {
		_, err := n.Pool.Exec(ctx,
			`UPDATE app_notifications
			    SET is_read = 1, read_at = NOW()
			  WHERE id = $1 AND user_id = $2`,
			notificationID, userID,
		)
		if err != nil {
			return MarkNotFound, err
		}
		return MarkOK, nil
	}

	// Broadcast row → insert into reads table (idempotent).
	_, err = n.Pool.Exec(ctx,
		`INSERT INTO app_notification_reads (notification_id, user_id)
		 VALUES ($1, $2)
		 ON CONFLICT (notification_id, user_id) DO NOTHING`,
		notificationID, userID,
	)
	if err != nil {
		return MarkNotFound, err
	}
	return MarkOK, nil
}

// ClearRead takes every notification the user has already READ out of their
// list, and returns how many rows that was.
//
// Unread rows are deliberately untouched: the app puts this behind a button,
// and a button that could throw away a case update the user has not opened yet
// is not a button worth having.
//
// Nothing is deleted. Rows the user owns get app_notifications.cleared_at;
// shared broadcast rows get it on the user's own app_notification_reads row,
// so clearing an announcement for one member leaves it in every other member's
// list. Migration 125 added both columns and List skips what they mark.
//
// Idempotent: a second call finds nothing left to stamp and reports 0.
func (n *Notifier) ClearRead(ctx context.Context, userID int64) (int64, error) {
	if userID <= 0 {
		return 0, errors.New("invalid args")
	}

	owned, err := n.Pool.Exec(ctx,
		`UPDATE app_notifications
		    SET cleared_at = NOW()
		  WHERE user_id = $1 AND is_read = 1 AND cleared_at IS NULL`,
		userID,
	)
	if err != nil {
		return 0, err
	}

	// A row exists in app_notification_reads only because this user read that
	// broadcast, so "every uncleared row of theirs" is exactly the broadcasts
	// they have read.
	broadcast, err := n.Pool.Exec(ctx,
		`UPDATE app_notification_reads
		    SET cleared_at = NOW()
		  WHERE user_id = $1 AND cleared_at IS NULL`,
		userID,
	)
	if err != nil {
		return 0, err
	}

	return owned.RowsAffected() + broadcast.RowsAffected(), nil
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
