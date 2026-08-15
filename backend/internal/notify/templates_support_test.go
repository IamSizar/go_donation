package notify

import (
	"regexp"
	"strings"
	"testing"
)

// Support-ticket notification templates.
//
// The support round trip has two halves and only one of them used to speak.
// A user filing a ticket was notified (SupportSubmittedMsg); a member of staff
// answering it was not, so `admin_reply` was written to the row and nothing
// ever told the user to go and read it. SupportRepliedMsg closes that, and
// these tests pin the two properties that make it useful rather than noisy.

// latinLetters matches any A–Z / a–z run. Used to prove a translated string is
// actually translated: Arabic copy with Latin letters in it is English that
// leaked through.
var latinLetters = regexp.MustCompile(`[A-Za-z]`)

// The reply notification must point at the ticket it answers, or tapping it in
// the app has nowhere to go.
func TestSupportRepliedMsg_PointsAtTheTicket(t *testing.T) {
	m := SupportRepliedMsg("Cannot upload my documents", 41)

	if m.Type != "support_ticket_replied" {
		t.Errorf("Type = %q, want %q", m.Type, "support_ticket_replied")
	}
	if m.RelatedEntityType != "support_tickets" {
		t.Errorf("RelatedEntityType = %q, want %q", m.RelatedEntityType, "support_tickets")
	}
	if m.RelatedEntityID != 41 {
		t.Errorf("RelatedEntityID = %d, want 41", m.RelatedEntityID)
	}
	// The subject names WHICH request was answered — a user with several open
	// tickets otherwise gets an alert they cannot place.
	if !strings.Contains(m.Body.En, "Cannot upload my documents") {
		t.Errorf("English body %q does not name the ticket subject", m.Body.En)
	}
	if !strings.Contains(m.Body.Ar, "Cannot upload my documents") {
		t.Errorf("Arabic body %q does not name the ticket subject", m.Body.Ar)
	}
}

// English and Arabic are supplied and genuinely different; Kurdish is left
// EMPTY on purpose.
//
// Both Kurdish locales are written in ARABIC SCRIPT, so Arabic text pasted
// into Ckb/Kmr looks plausible and is wrong — a mistake this project has
// already made once and had to revert. Send() stores an empty slot as NULL and
// every client falls back to English, which is legible and honest. This test
// exists so a later "helpful" fill-in has to be a deliberate act by someone
// who reads this comment, not a silent paste.
func TestSupportRepliedMsg_ArabicIsRealAndKurdishIsLeftToATranslator(t *testing.T) {
	m := SupportRepliedMsg("Payment did not arrive", 7)

	if strings.TrimSpace(m.Title.En) == "" || strings.TrimSpace(m.Body.En) == "" {
		t.Fatal("English title/body must never be empty — it is every locale's fallback")
	}
	if strings.TrimSpace(m.Title.Ar) == "" || strings.TrimSpace(m.Body.Ar) == "" {
		t.Fatal("Arabic title/body must be supplied — Arabic is the primary UI language")
	}
	if m.Title.Ar == m.Title.En {
		t.Errorf("Arabic title %q is identical to the English one — untranslated", m.Title.Ar)
	}
	// The subject is caller-supplied and may legitimately be English, so only
	// the title is checked for leaked Latin script.
	if latinLetters.MatchString(m.Title.Ar) {
		t.Errorf("Arabic title %q contains Latin letters", m.Title.Ar)
	}

	if m.Title.Ckb != "" || m.Body.Ckb != "" {
		t.Errorf("Sorani must stay empty until a native speaker supplies it, got title=%q body=%q",
			m.Title.Ckb, m.Body.Ckb)
	}
	if m.Title.Kmr != "" || m.Body.Kmr != "" {
		t.Errorf("Badini must stay empty until a native speaker supplies it, got title=%q body=%q",
			m.Title.Kmr, m.Body.Kmr)
	}
}
