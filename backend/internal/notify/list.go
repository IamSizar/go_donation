package notify

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Notification mirrors the JSON shape from the PHP GET /api/notifications.
type Notification struct {
	ID                   int64     `json:"id"`
	UserID               *int      `json:"user_id"`
	RoleID               *int      `json:"role_id"`
	Title                string    `json:"title"`
	TitleAr              *string   `json:"title_ar"`
	TitleSorani          *string   `json:"title_sorani"`
	TitleBadini          *string   `json:"title_badini"`
	Body                 string    `json:"body"`
	BodyAr               *string   `json:"body_ar"`
	BodySorani           *string   `json:"body_sorani"`
	BodyBadini           *string   `json:"body_badini"`
	NotificationType     *string   `json:"notification_type"`
	NotificationCategory string    `json:"notification_category"`
	Priority             int       `json:"priority"`
	ActionURL            *string   `json:"action_url"`
	RelatedEntityType    *string   `json:"related_entity_type"`
	RelatedEntityID      *int64    `json:"related_entity_id"`
	IsRead               int       `json:"is_read"`
	ReadAt               *time.Time `json:"read_at"`
	CreatedAt            time.Time `json:"created_at"`
}

// ListFilter narrows the notifications query.
type ListFilter struct {
	UserID     int64  // 0 = anonymous (only system-wide rows)
	RoleID     int    // 0 = don't filter
	Category   string // "" = all  | "normal","urgent","payment","campaign","system","reminder"
	Type       string // "" = all
	ReadStatus string // "all" (default) | "unread" | "read"
	Limit      int    // default 50
}

// List returns notifications visible to the user, with effective read status
// computed against app_notification_reads for broadcast rows (user_id IS NULL).
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
	if f.UserID > 0 {
		uidArg := nextArg(f.UserID)
		where = append(where, "(n.user_id = "+uidArg+" OR n.user_id IS NULL)")
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
