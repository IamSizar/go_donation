package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// GuestSupportThreadOnly — R2 #16. A visitor (guest account) may talk to
// support, and only to support: on /chats/:id/* a guest passes only when the
// thread is a support thread AND the other party is staff (staff_tier other
// than 'user'). Every other caller passes straight through (the handler's own
// participant check still applies to everyone).
func (h *ChatHandler) GuestSupportThreadOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		u, ok := auth.UserFromGin(c)
		if !ok || u == nil || !u.IsGuest {
			c.Next()
			return
		}
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		allowed := false
		if err == nil && h.Pool != nil {
			_ = h.Pool.QueryRow(c.Request.Context(),
				`SELECT EXISTS (
				   SELECT 1 FROM chat_threads t
				   JOIN users other ON other.id = CASE WHEN t.donor_user_id = $2
				                                      THEN t.owner_user_id
				                                      ELSE t.donor_user_id END
				   WHERE t.id = $1 AND t.kind = 'support'
				     AND $2 IN (t.donor_user_id, t.owner_user_id)
				     AND COALESCE(other.staff_tier, 'user') <> 'user')`,
				id, u.UserID).Scan(&allowed)
		}
		if !allowed {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"status": "error",
				"error":  "Full registration is required for this conversation.",
				"code":   "guest_restricted",
			})
			return
		}
		c.Next()
	}
}

// guestSupportThreadIDs — the support threads (with a staff counterpart) the
// guest is party to; the only threads a visitor may list or open.
func (h *ChatHandler) guestSupportThreadIDs(c *gin.Context, userID int64) (map[int64]bool, error) {
	out := map[int64]bool{}
	rows, err := h.Pool.Query(c.Request.Context(), `
		SELECT t.id FROM chat_threads t
		JOIN users other ON other.id = CASE WHEN t.donor_user_id = $1
		                                   THEN t.owner_user_id
		                                   ELSE t.donor_user_id END
		WHERE t.kind = 'support' AND $1 IN (t.donor_user_id, t.owner_user_id)
		  AND COALESCE(other.staff_tier, 'user') <> 'user'`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}
