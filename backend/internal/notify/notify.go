// Package notify is the central notification helper for the Go backend.
//
// It mirrors module_notify_user() in percentage/api/_module_helpers.php:
// it inserts a row into app_notifications (deduped by user+title+body+type)
// and resolves a category + priority based on the notification type string.
//
// FCM push delivery is intentionally a no-op stub here — the PHP API also
// only writes to the DB; the admin panel sends pushes out-of-band. When/if
// we add real FCM HTTP v1 delivery, the only thing that needs to change is
// the Send() function.
package notify

import (
	"context"
	"errors"
	"log"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Notifier struct {
	Pool *pgxpool.Pool
	fcm  *fcmClient // nil when no Firebase credentials are configured
}

// New constructs a Notifier and tries to load the Firebase service account
// (FIREBASE_CREDENTIALS_FILE, default ./firebase-credentials.json). Failure
// to load is logged but non-fatal — in-DB notifications still work.
func New(pool *pgxpool.Pool) *Notifier {
	n := &Notifier{Pool: pool}
	if client, err := loadFCMClient(); err != nil {
		log.Printf("[notify] FCM credentials load failed: %v (push delivery disabled)", err)
	} else if client != nil {
		log.Printf("[notify] FCM enabled (project=%s)", client.projectID)
		n.fcm = client
	} else {
		log.Printf("[notify] no FCM credentials found; push delivery disabled")
	}
	return n
}

// LocalText holds the same piece of copy in all four supported locales.
// Empty strings are allowed for fields a translator hasn't filled in yet —
// the Flutter renderer falls back EN → AR → Sorani → Badini, so partial
// coverage still produces a readable notification.
//
// Locale keys:
//
//	En  — English (canonical / fallback)
//	Ar  — Arabic (Modern Standard)
//	Ckb — Kurdish Sorani (Central Kurdish, ISO 639-3 "ckb")
//	Kmr — Kurdish Badini / Kurmanji (Northern Kurdish, ISO 639-3 "kmr")
type LocalText struct {
	En, Ar, Ckb, Kmr string
}

// LocalizedMessage is everything the templates.go builders return. The
// Notifier's Send() method consumes it and persists / fans out the push.
//
//	Title — required (en is the absolute minimum)
//	Body  — required
//	Type  — notification_type column; drives category + priority below
//	RelatedEntityType + RelatedEntityID — optional FK reference
//	ActionURL — optional deep-link the mobile app will navigate to on tap
type LocalizedMessage struct {
	Title             LocalText
	Body              LocalText
	Type              string
	RelatedEntityType string
	RelatedEntityID   int64
	ActionURL         string
}

// Send writes one row to app_notifications with all 4 language columns
// populated, then fires a best-effort FCM push. Returns 0 if a duplicate
// (same user + EN title + EN body + type) already exists.
//
// This is the preferred API. NotifyUser remains as a thin back-compat
// wrapper for old EN+AR callsites.
func (n *Notifier) Send(ctx context.Context, userID int64, m LocalizedMessage) (int64, error) {
	if userID <= 0 {
		return 0, errors.New("invalid userID")
	}
	if m.Title.En == "" || m.Body.En == "" {
		return 0, errors.New("LocalizedMessage requires at least Title.En + Body.En")
	}

	// #31 — respect the user's notification switch. When off, skip silently
	// (no in-app row, no push). A query error defaults to enabled so a transient
	// failure never mutes a user.
	notifEnabled := 1
	if err := n.Pool.QueryRow(ctx,
		`SELECT notifications_enabled FROM users WHERE id = $1`, userID).Scan(&notifEnabled); err == nil && notifEnabled == 0 {
		return 0, nil
	}

	category := resolveCategory(m.Type)
	priority := defaultPriority(category)

	// Dedupe: same user + EN title + EN body + type. Matches the PHP
	// helper's behavior so re-running an admin action doesn't double-fire.
	var existing int64
	err := n.Pool.QueryRow(ctx,
		`SELECT id FROM app_notifications
		  WHERE user_id = $1 AND title = $2 AND body = $3 AND notification_type = $4
		  LIMIT 1`,
		userID, m.Title.En, m.Body.En, m.Type,
	).Scan(&existing)
	if err == nil {
		return 0, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return 0, err
	}

	// Optional pointer-to-nil args so NULL is stored when fields aren't set.
	var actionArg, retArg any
	if m.ActionURL != "" {
		actionArg = m.ActionURL
	}
	if m.RelatedEntityType != "" {
		retArg = m.RelatedEntityType
	}
	var reIDArg any
	if m.RelatedEntityID > 0 {
		reIDArg = m.RelatedEntityID
	}

	// nilIfEmpty keeps NULLs out of the optional language columns so the
	// Flutter renderer's fallback chain works cleanly. Required EN columns
	// (title, body) go in as plain strings.
	nilIfEmpty := func(s string) any {
		if s == "" {
			return nil
		}
		return s
	}

	var id int64
	err = n.Pool.QueryRow(ctx,
		`INSERT INTO app_notifications
		   (user_id,
		    title,        title_ar,        title_sorani,        title_badini,
		    body,         body_ar,         body_sorani,         body_badini,
		    notification_type, notification_category, priority,
		    action_url, related_entity_type, related_entity_id, is_read)
		 VALUES ($1,
		         $2, $3, $4, $5,
		         $6, $7, $8, $9,
		         $10, $11, $12,
		         $13, $14, $15, 0)
		 RETURNING id`,
		userID,
		m.Title.En, nilIfEmpty(m.Title.Ar), nilIfEmpty(m.Title.Ckb), nilIfEmpty(m.Title.Kmr),
		m.Body.En,  nilIfEmpty(m.Body.Ar),  nilIfEmpty(m.Body.Ckb),  nilIfEmpty(m.Body.Kmr),
		m.Type, category, priority,
		actionArg, retArg, reIDArg,
	).Scan(&id)
	if err != nil {
		return 0, err
	}

	// Best-effort FCM push. Phase 27.3 — passes the full LocalizedMessage
	// so sendPush can deliver each of the user's devices its preferred
	// language (registered at /api/notifications/device time). Each
	// device falls back to EN when its locale slot is empty.
	go func() {
		bg, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = n.sendPush(bg, userID, m)
	}()

	return id, nil
}

// Broadcast fans Send out to every active user. If roleID > 0, only users
// with that role receive the notification. Returns the number of
// successful inserts (deduplicated rows are not counted).
//
// Used for things like "new partner added", "new media post", "new
// volunteer mission posted" — content that's relevant to a class of users
// rather than one specific person.
func (n *Notifier) Broadcast(ctx context.Context, roleID int, m LocalizedMessage) (int, error) {
	q := `SELECT id FROM users WHERE active = 1`
	args := []any{}
	if roleID > 0 {
		q += ` AND role_id = $1`
		args = append(args, roleID)
	}
	rows, err := n.Pool.Query(ctx, q, args...)
	if err != nil {
		return 0, err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	sent := 0
	for _, uid := range ids {
		// Each send is independent; one failure shouldn't abort the rest.
		// Errors are logged but otherwise swallowed.
		if newID, err := n.Send(ctx, uid, m); err != nil {
			log.Printf("[notify] broadcast send user=%d failed: %v", uid, err)
		} else if newID > 0 {
			sent++
		}
	}
	return sent, nil
}

// BroadcastToStaff sends a notification to every active STAFF member — the
// dashboard operators who review submissions. Staff are identified by is_admin=1
// or a staff staff_tier (super_admin/admin/supervisor/employee), NOT by role_id
// (role_id is the app-side role: donor/beneficiary/volunteer). Use this for
// "new X needs review" alerts so they land on the admin dashboard bell.
// Best-effort: individual send failures are logged, not fatal.
func (n *Notifier) BroadcastToStaff(ctx context.Context, m LocalizedMessage) (int, error) {
	rows, err := n.Pool.Query(ctx,
		`SELECT id FROM users
		  WHERE active = 1
		    AND (is_admin = 1
		         OR staff_tier IN ('super_admin','admin','supervisor','employee'))`)
	if err != nil {
		return 0, err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	sent := 0
	for _, uid := range ids {
		if newID, err := n.Send(ctx, uid, m); err != nil {
			log.Printf("[notify] staff broadcast send user=%d failed: %v", uid, err)
		} else if newID > 0 {
			sent++
		}
	}
	return sent, nil
}

// NotifyUser is kept for back-compat with EN+AR callsites in extras.go,
// beneficiary.go, marketplace.go that haven't been migrated to Send yet.
// New code should use Send(LocalizedMessage) instead.
//
// Returns the inserted notification id (0 if deduped).
func (n *Notifier) NotifyUser(
	ctx context.Context,
	userID int64,
	title, titleAr, body, bodyAr, notificationType string,
	actionURL, relatedEntityType string,
	relatedEntityID int64,
) (int64, error) {
	return n.Send(ctx, userID, LocalizedMessage{
		Title:             LocalText{En: title, Ar: titleAr},
		Body:              LocalText{En: body, Ar: bodyAr},
		Type:              notificationType,
		ActionURL:         actionURL,
		RelatedEntityType: relatedEntityType,
		RelatedEntityID:   relatedEntityID,
	})
}

// resolveCategory mirrors the case mapping in module_notify_user() PHP.
func resolveCategory(notificationType string) string {
	t := strings.ToLower(notificationType)
	switch {
	case strings.Contains(t, "urgent"), strings.Contains(t, "support"), strings.Contains(t, "case"):
		return "urgent"
	case strings.Contains(t, "payment"), strings.Contains(t, "donation"), strings.Contains(t, "sponsorship"):
		return "payment"
	case strings.Contains(t, "campaign"), strings.Contains(t, "project"),
		t == "media_post" || t == "news" || t == "activity":
		return "campaign"
	case strings.Contains(t, "reminder"), strings.Contains(t, "due"):
		return "reminder"
	case strings.Contains(t, "system"), strings.Contains(t, "admin"):
		return "system"
	default:
		return "normal"
	}
}

func defaultPriority(category string) int {
	switch category {
	case "urgent":
		return 80
	case "payment":
		return 60
	case "campaign":
		return 35
	case "system":
		return 20
	case "reminder":
		return 15
	default:
		return 0
	}
}
