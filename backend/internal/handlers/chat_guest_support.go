// chat_guest_support.go — K20's visitor half: what a زائر (guest) may reach.
//
// # THE DECISION, AND WHY IT IS NOT "GUESTS GET THE GENERAL CHAT"
//
// K20 asks for a chat platform reaching "مستفيدين، متبرعين، وزوار". The first
// two already have one — donor↔owner, case-volunteer, marriage and support
// threads all exist for signed-in accounts. Visitors had nothing at all: every
// chat write route carried auth.RequireNotGuest(), /chats/support included.
//
// That was not merely incomplete, it contradicted the product. Section 27's
// guest screen list (internal/guest/guest.go) ships `support` DefaultEnabled —
// the app offers a visitor "support options" and the server then refused the
// only channel behind it.
//
// But a general chat for guests is not the fix. A guest account is a username
// and a six-character password: no phone, no OTP, no verification whatsoever
// (see GuestRegister). They are free, instant and unlimited. Any channel a
// guest can aim at another USER is an unmoderated spam and harassment surface
// pointed at the beneficiaries this product exists to protect — and it would
// undo K19's supervision work in the same release that added it.
//
// So the answer is narrow and deliberate: A GUEST MAY TALK TO STAFF, AND TO
// NOBODY ELSE. One thread, opened by them, answered by support.
//
// # THE MODERATION IS STRUCTURAL, NOT ADDED
//
// Nothing new was invented to police this. RequestThread already creates a
// support thread as 'pending' and PostMessage already requires 'active', so a
// staff member must ACCEPT before a guest can say a word — and can decline. And
// because there is exactly one thread per (user, support) pair, a guest cannot
// open a second one to spam through. The existing flow was already the right
// shape; it was just switched off for visitors.
package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chat"
)

// refuseGuestPeerMessage keeps a guest inside the one conversation they are
// allowed. It reports whether the message was REFUSED — when it returns true it
// has already written the response and the caller must stop.
//
// Opening /chats/:id/messages to guests (K20) removed the blanket
// RequireNotGuest() from that route, so this is what stops it from opening
// EVERY thread. A guest may post only where the counterpart is staff.
//
// In practice a guest cannot become party to a donor↔beneficiary thread today
// — /chats/request is still RequireNotGuest, and the owner-initiated path
// demands a prior donation, which guests cannot make. This guard exists because
// "in practice, today" is not a security boundary: it makes the rule explicit
// so a future route that creates threads cannot silently widen guest reach.
//
// The refusal reuses the "guest_restricted" code the app already handles, so a
// visitor sees the existing Upgrade Account prompt rather than a new error
// state — which is the correct next step for them.
func (h *ChatHandler) refuseGuestPeerMessage(c *gin.Context, thread chat.Thread, sender *auth.ResolvedUser) bool {
	if sender == nil || !sender.IsGuest {
		return false
	}
	peer, err := h.Store.IsPeerThread(c.Request.Context(), thread)
	if err != nil {
		// IsPeerThread fails CLOSED (reports true). For a guest that means the
		// message is refused, which is the safe direction: a visitor briefly
		// unable to reach support is recoverable, a visitor reaching a
		// beneficiary is not.
		log.Printf("[chat] K20 party-tier lookup failed on thread %d, refusing guest: %v", thread.ID, err)
	}
	if !peer {
		return false // counterpart is staff — this is the support conversation
	}
	c.JSON(http.StatusForbidden, gin.H{
		"success": false,
		"code":    "guest_restricted",
		"error":   "Guest accounts can message support only. Please upgrade your account to chat with other members.",
	})
	return true
}
