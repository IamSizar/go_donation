// guest_empty_list.go — GuestGetsEmptyList, the guest guard on the mobile chat
// LIST routes (OPOS #26354). The messages routes beside those lists refuse a
// guest outright with auth.RequireNotGuest; this file explains why the lists
// answer differently.
package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
)

// GuestGetsEmptyList answers a guest session on a chat LIST route with an
// ordinary, successful, empty list, and aborts the chain there. The list
// handler behind it never runs, so no thread is ever queried for, or returned
// to, a guest.
//
// Why an empty list and not auth.RequireNotGuest's 403: apps already installed
// on guests' phones fetch GET /api/chats on every dashboard session and poll it
// every few seconds, and they treat any non-2xx answer as a failed load. A 403
// there turned a guest's Messages tab into "Unable to load your chats." with a
// Retry that can never succeed. An empty list lets those apps show their normal
// empty state without an app update, and the guest still sees no thread data.
//
// The body is exactly what ChatHandler.List and MarriageChatHandler.List send a
// signed-in user with no threads, {"success": true, "items": []} — both stores
// start from an empty, non-nil slice — so the app cannot tell the two apart.
//
// MUST run after auth.RequireBearer, which resolves the user. A caller that is
// not a guest passes straight through to the handler — and so does a request
// with no resolved user. That is safe only because RequireBearer has already
// refused such requests and both list handlers answer a nil user with 401
// themselves; do not put this guard in front of a handler without that check.
func GuestGetsEmptyList() gin.HandlerFunc {
	return func(c *gin.Context) {
		u, ok := auth.UserFromGin(c)
		if !ok || u == nil || !u.IsGuest {
			c.Next()
			return
		}
		c.AbortWithStatusJSON(http.StatusOK, gin.H{"success": true, "items": []any{}})
	}
}
