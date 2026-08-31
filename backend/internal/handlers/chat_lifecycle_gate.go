// chat_lifecycle_gate.go — the SERVER-SIDE refusal that every chat send path
// runs before a message is stored.
//
// This is the enforcement. The Flutter app hides its composer on a paused or
// ended chat and the dashboard greys out its reply box, but neither is a
// rule: a crafted request bypasses both. Nothing is stored, and therefore
// nothing is pushed, unless this passes.
//
// It is deliberately one function used by all four chat systems AND by both
// the participant and the staff send paths. A pause that staff could talk
// through would not be a pause.
package handlers

import (
	"errors"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/chatlifecycle"
)

// chatLifecycleRefusedCode is the machine-readable marker the app switches on
// to pick its own localised banner. The English `error` string travels beside
// it for any client that does not know the code.
const chatLifecycleRefusedCode = "chat_lifecycle_closed"

// refuseIfNotSendable writes the refusal response and returns true when the
// caller must stop. The response always says WHY — the lifecycle state and,
// when staff gave one, their reason in their own words.
//
// 409 Conflict rather than 403: the sender is not forbidden as a person, the
// conversation is in a state that does not accept messages. The existing
// "chat is not active yet" refusal on the same routes already uses 409, so a
// client that handles one handles both.
func refuseIfNotSendable(c *gin.Context, pool *pgxpool.Pool, kind chatlifecycle.Kind, threadID int64) bool {
	err := chatlifecycle.EnsureSendable(c.Request.Context(), pool, kind, threadID)
	if err == nil {
		return false
	}
	var refused *chatlifecycle.SendRefusedError
	if errors.As(err, &refused) {
		c.JSON(http.StatusConflict, gin.H{
			"success":          false,
			"code":             chatLifecycleRefusedCode,
			"lifecycle":        refused.State.Lifecycle,
			"lifecycle_reason": refused.State.Reason,
			"error":            refused.UserMessage(),
		})
		return true
	}
	if errors.Is(err, chatlifecycle.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
		return true
	}
	// Fail CLOSED. If we cannot read the thread's state we cannot know that it
	// is open, and letting the message through "because the check broke" is
	// exactly how a paused conversation starts working again by accident.
	log.Printf("[chat-lifecycle] gate failed for %s/%d: %v", kind, threadID, err)
	c.JSON(http.StatusInternalServerError, gin.H{"success": false,
		"error": "Could not check this chat's status. Please try again."})
	return true
}

// refuseIfArchivedForParticipant hides an archived thread from the people in
// it, on the read path.
//
// Archiving is a staff moderation action whose whole purpose is that the
// participants stop seeing the conversation, so leaving the messages endpoint
// open would defeat it: the thread would vanish from the list while a
// bookmarked id still served the whole history. Staff read through their own
// admin endpoints, which are unfiltered by design.
//
// 404 rather than 403 — from the participant's side the thread is simply not
// there, and saying "this exists but is hidden from you" would leak the
// moderation decision.
func refuseIfArchivedForParticipant(c *gin.Context, pool *pgxpool.Pool, kind chatlifecycle.Kind, threadID int64) bool {
	state, err := chatlifecycle.Load(c.Request.Context(), pool, kind, threadID)
	if err != nil {
		if errors.Is(err, chatlifecycle.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
			return true
		}
		log.Printf("[chat-lifecycle] archive check failed for %s/%d: %v", kind, threadID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return true
	}
	if state.IsArchived {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Chat not found."})
		return true
	}
	return false
}

// mergeChatLifecycle adds the {lifecycle, reason, archived} triple to a
// thread-reading response, so the app can render the banner that replaces its
// composer instead of letting the user type into a chat that will refuse
// them. Best effort: a state that cannot be read is reported as `open` with
// the failure logged, because the SEND path re-checks and fails closed
// anyway — a wrong banner is a cosmetic bug, a wrong refusal is not.
func mergeChatLifecycle(c *gin.Context, pool *pgxpool.Pool, kind chatlifecycle.Kind, threadID int64, body gin.H) gin.H {
	state, err := chatlifecycle.Load(c.Request.Context(), pool, kind, threadID)
	if err != nil {
		log.Printf("[chat-lifecycle] could not read state for %s/%d: %v", kind, threadID, err)
		state = chatlifecycle.State{Lifecycle: chatlifecycle.StateOpen}
	}
	body["lifecycle"] = state.Lifecycle
	body["lifecycle_reason"] = state.Reason
	body["is_archived"] = state.IsArchived
	return body
}
