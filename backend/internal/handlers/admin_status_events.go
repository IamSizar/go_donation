package handlers

import (
	"context"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/events"
)

// logAdminUserEvent — Admin Notification System.
//
// Appends an admin-sourced row to app_events whenever a staff member creates or
// modifies a USER ACCOUNT. Because the dashboard Notification Center (the live
// feed) reads app_events, this surfaces the change to the Primary Administrator
// and every other dashboard user immediately, and — since app_events is
// append-only — it is permanently recorded as an audit entry. Purging one is
// gated to the Super-Admin (see EventsHandler.AdminDelete).
//
//   action  — short verb: create | role | tier | password | active | admin | status
//   newVal  — the new value where meaningful (raw enum, so the FRONTEND localizes
//             it to the viewer's language). Pass "" when there's no value to show
//             (and NEVER pass a password).
//
// Best-effort: a logging failure must never fail the underlying admin action, so
// all errors are swallowed. Runs synchronously (the row exists before we return)
// so the audit trail can't be lost to a crash between the update and the insert.
func (h *AdminStatusHandler) logAdminUserEvent(c *gin.Context, targetID int64, action, newVal string) {
	if h.Events == nil {
		return
	}
	ctx := c.Request.Context()

	// Denormalise the affected account's name/phone so the feed renders without a
	// join and the entry survives the user later being deleted.
	name, phone := h.userNamePhone(ctx, targetID)

	meta := map[string]any{}
	if newVal != "" {
		meta["new"] = newVal
	}
	if actor, ok := auth.UserFromGin(c); ok && actor != nil {
		meta["actor_user_id"] = actor.UserID
		meta["actor_phone"] = actor.Phone
		meta["actor_tier"] = actor.StaffTier
		aName, aPhone := h.userNamePhone(ctx, actor.UserID)
		if disp := firstNonEmpty(aName, aPhone); disp != "" {
			meta["actor_name"] = disp
		}
	}

	tid := targetID
	_, _ = h.Events.Insert(ctx, events.Event{
		EventType:    "admin_user_" + action,
		Module:       "users",
		Action:       action,
		Source:       "admin",
		UserID:       &tid,
		Name:         name,
		Number:       phone,
		NumberDigits: digitsOnly(phone),
		EntityID:     &tid,
		Metadata:     meta,
		CreatedAtMs:  time.Now().UnixMilli(),
	})
}

// userNamePhone returns (full_name, phone) for a user id, empty strings when the
// row or profile is missing. Used to denormalise actor + target identity onto
// the event row.
func (h *AdminStatusHandler) userNamePhone(ctx context.Context, id int64) (string, string) {
	var name, phone string
	_ = h.Pool.QueryRow(ctx,
		`SELECT COALESCE(p.full_name, ''), COALESCE(u.phone, '')
		   FROM users u
		   LEFT JOIN user_profiles p ON p.user_id = u.id
		  WHERE u.id = $1`, id).Scan(&name, &phone)
	return name, phone
}

// roleName maps a numeric role_id to the machine label the frontend localizes
// (via statusLabel). Unknown / cleared roles return "".
func roleName(roleID int) string {
	switch roleID {
	case 1:
		return "donor"
	case 2:
		return "beneficiary"
	case 3:
		return "volunteer"
	case 4:
		return "employee"
	default:
		return ""
	}
}
