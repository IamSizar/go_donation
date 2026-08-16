// chat_contact_block.go — K19's write-path guard: the supervised
// donor↔beneficiary thread refuses a message carrying a phone number or an
// email address, tells the sender why, and records the attempt for staff.
//
// Separate from chat.go because that file is already at the size limit and
// because this is one self-contained rule. chat.go's PostMessage calls exactly
// one function from here.
package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// contactBlockedCode is the machine-readable reason the app switches on to show
// its own localized wording, following the "guest_restricted" precedent in
// internal/auth/middleware.go. The English `error` string is the fallback for
// any client that does not know the code, exactly as everywhere else in this
// package — no Arabic screen is expected to render it.
const contactBlockedCode = "contact_details_blocked"

// refuseContactDetails enforces K19's "منع تبادل البيانات الشخصية منعاً
// للابتزاز" on the message write path. It reports whether the message was
// REFUSED — when it returns true it has already written the response and the
// caller must stop.
//
// # WHY REFUSE AND NOT STRIP
//
// A stripped message looks delivered. The sender then waits for a call that
// can never come, and — worse for the thing this is protecting against —
// learns nothing, so they try again with heavier obfuscation until something
// gets through. A refusal states the rule once. It is also the only option
// that actually holds: PostMessage fans out an 80-character push preview of
// every message, so a number that survived to the database would already have
// left the server inside a notification payload. The write is the only
// airtight place.
//
// # WHO IS EXEMPT, AND WHY
//
// Two exemptions, both deliberate:
//
//   - The SENDER is staff. K19 casts the employee as mediator, and a mediator
//     relaying a number on someone's behalf is the supervised channel working
//     as designed. staff_tier is the authority; is_admin is legacy and unread.
//   - The THREAD is not between two members of the public. POST
//     /api/chats/support (#45) opens a thread on the same table with the
//     support account as "owner", and a user giving support their own number
//     is not an extortion risk — it is the support request. See
//     chat.Store.IsPeerThread.
func (h *ChatHandler) refuseContactDetails(c *gin.Context, thread chat.Thread, sender *auth.ResolvedUser, body string) bool {
	// Exemption 1 — staff relay.
	if sender != nil && permissions.TierFrom(sender.StaffTier) != permissions.TierUser {
		return false
	}

	// Exemption 2 — one of the parties is staff, so this is a support or
	// staff-mediated thread rather than the donor↔beneficiary pair K19 covers.
	peer, err := h.Store.IsPeerThread(c.Request.Context(), thread)
	if err != nil {
		// IsPeerThread fails CLOSED (returns true). Log the cause and carry on
		// filtering — a support user briefly inconvenienced is a far cheaper
		// failure than a leaked number in the thread this row is about.
		log.Printf("[chat] K19 party-tier lookup failed on thread %d, filtering anyway: %v", thread.ID, err)
	}
	if !peer {
		return false
	}

	finding := moderation.ScanContact(body)
	if !finding.Blocked() {
		return false
	}

	// Record for the supervisor. A failure here must never become a failure to
	// block — the refusal below happens either way.
	if err := h.Store.RecordContactBlock(c.Request.Context(), thread.ID, sender.UserID,
		string(finding.Kind), finding.Count, finding.Redacted); err != nil {
		log.Printf("[chat] K19 could not record blocked attempt on thread %d: %v", thread.ID, err)
	}

	c.JSON(http.StatusUnprocessableEntity, gin.H{
		"success": false,
		"code":    contactBlockedCode,
		"kind":    string(finding.Kind),
		"error":   contactBlockedMessage(finding.Kind),
	})
	return true
}

// contactBlockedMessage is the fallback English wording. It follows the error
// rules the rest of the product is held to: say what happened, why, and what to
// do next — never just "rejected".
func contactBlockedMessage(kind moderation.ContactKind) string {
	switch kind {
	case moderation.ContactPhone:
		return "Phone numbers cannot be shared in this chat. It is supervised for your safety — please keep the conversation here, and ask the responsible staff member if you need to arrange contact."
	case moderation.ContactEmail:
		return "Email addresses cannot be shared in this chat. It is supervised for your safety — please keep the conversation here, and ask the responsible staff member if you need to arrange contact."
	default:
		return "Phone numbers and email addresses cannot be shared in this chat. It is supervised for your safety — please keep the conversation here, and ask the responsible staff member if you need to arrange contact."
	}
}

// ===== Admin =====

// AdminContactBlocks — GET /api/admin/chats/:id/contact-blocks.
//
// The monitor half of K19. One refused message is a misunderstanding; the same
// sender refused repeatedly is the pattern worth acting on, and it is only
// visible if someone can see the list. Behind the same `messages:view`
// permission as the thread's messages, because it is the same conversation.
//
// The bodies returned here are redacted at the point of capture (migration
// 116) — this endpoint cannot leak a number because no number was stored.
func (h *ChatHandler) AdminContactBlocks(c *gin.Context) {
	if _, ok := auth.UserFromGin(c); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": "Unauthorized."})
		return
	}
	id, ok := parseID(c)
	if !ok {
		return
	}
	if _, err := h.Store.GetThread(c.Request.Context(), id); err != nil {
		h.chatErr(c, err)
		return
	}
	items, err := h.Store.ListContactBlocks(c.Request.Context(), id)
	if err != nil {
		log.Printf("[chat] listing contact blocks for thread %d: %v", id, err)
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error."})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "items": items})
}
