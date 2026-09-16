// chat_group_contact_block.go — K19's contact-info filter, adapted for
// staff-mediated group chats. See chat_contact_block.go for the full "why
// refuse, not strip" rationale, which applies unchanged here.
//
// The exemption rule is NOT identical to the donor↔owner chat's. There, a
// thread with ANY staff party skips filtering entirely. A masked group
// ALWAYS includes staff by construction (spec §1), so reusing that
// exemption verbatim would silently disable filtering for every message any
// masked group ever carries — exactly the gap this file exists to avoid.
// Filtering here is keyed on the GROUP's kind, never on who else is present:
// masked groups filter every non-staff sender; team groups never filter at
// all, since real names are already visible and there is no masking
// invariant left to protect.
package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/chatgroups"
	"github.com/karam-flutter/humanitarian-backend/internal/moderation"
	"github.com/karam-flutter/humanitarian-backend/internal/permissions"
)

// refuseGroupContactDetails reports whether the message was REFUSED — when
// it returns true it has already written the response and the caller must
// stop. Reuses contactBlockedCode/contactBlockedMessage from
// chat_contact_block.go (same package, same wording — one rule, one voice).
func (h *ChatGroupHandler) refuseGroupContactDetails(c *gin.Context, group chatgroups.GroupDetail, sender *auth.ResolvedUser, body string) bool {
	if group.Kind != chatgroups.KindMasked {
		return false
	}
	if sender != nil && permissions.TierFrom(sender.StaffTier) != permissions.TierUser {
		return false // staff relay — same exemption as the donor↔owner chat
	}

	finding := moderation.ScanContact(body)
	if !finding.Blocked() {
		return false
	}

	if err := h.Store.RecordContactBlock(c.Request.Context(), group.ID, sender.UserID,
		string(finding.Kind), finding.Count, finding.Redacted); err != nil {
		log.Printf("[chat-group] could not record blocked attempt on group %d: %v", group.ID, err)
	}

	c.JSON(http.StatusUnprocessableEntity, gin.H{
		"success": false,
		"code":    contactBlockedCode,
		"kind":    string(finding.Kind),
		"error":   contactBlockedMessage(finding.Kind),
	})
	return true
}
