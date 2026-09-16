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

// All four locales are supplied, and each is genuinely different from the
// others.
//
// Kurdish was empty here until 2026-09-16, when the owner asked for a
// best-effort draft. What this test still guards is the mistake that made the
// empty slot worth having: both Kurdish locales are written in ARABIC SCRIPT,
// so Arabic text pasted into Ckb/Kmr looks plausible and is wrong — something
// this project has already done once and had to revert. So the Kurdish must be
// present and must NOT equal the Arabic or the English.
func TestSupportRepliedMsg_EveryLocaleIsSuppliedAndDistinct(t *testing.T) {
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

	for _, k := range []struct {
		name        string
		title, body string
	}{
		{"Sorani", m.Title.Ckb, m.Body.Ckb},
		{"Badini", m.Title.Kmr, m.Body.Kmr},
	} {
		if strings.TrimSpace(k.title) == "" || strings.TrimSpace(k.body) == "" {
			t.Errorf("%s title/body must be supplied", k.name)
			continue
		}
		if k.title == m.Title.Ar || k.body == m.Body.Ar {
			t.Errorf("%s is identical to the Arabic — Arabic pasted into a Kurdish slot", k.name)
		}
		if k.title == m.Title.En || k.body == m.Body.En {
			t.Errorf("%s is identical to the English — untranslated", k.name)
		}
		if latinLetters.MatchString(k.title) {
			t.Errorf("%s title %q contains Latin letters", k.name, k.title)
		}
		if !strings.Contains(k.body, "Payment did not arrive") {
			t.Errorf("%s body %q dropped the ticket subject", k.name, k.body)
		}
	}
	if m.Title.Ckb == m.Title.Kmr && m.Body.Ckb == m.Body.Kmr {
		t.Error("Sorani and Badini are word-for-word identical — one was copied into the other")
	}
}
