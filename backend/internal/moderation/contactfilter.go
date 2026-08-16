// contactfilter.go — K19's "منعاً للابتزاز" personal-data block: detecting a
// phone number or an email address inside a supervised chat message.
//
// # WHY THIS LIVES IN moderation
//
// The package already owns "content that must not go through" for comments.
// This is the same question asked of chat messages, so it shares the home but
// not the mechanism: bannedwords.go is an admin-managed list read from the
// database, while this is a fixed structural detector with no configuration
// and no I/O. Keeping them in separate files keeps that difference visible.
//
// # WHY REFUSE RATHER THAN REDACT
//
// The caller (handlers/chat.go) rejects the message and tells the sender why,
// instead of silently stripping the number. Three reasons, in order of weight:
//
//  1. A sender whose number was silently stripped believes it went through and
//     waits for a call that never comes. Refusing states the rule once and the
//     user adapts; stripping teaches nothing and invites them to keep trying
//     with heavier obfuscation until something slips past.
//  2. Redacting at DISPLAY time cannot work here at all. Every new message
//     fans out an 80-character push preview (ChatNewMessageMsg), so the raw
//     number would leave the server inside the notification payload before any
//     display filter ran. The only place the block is airtight is the write.
//  3. The row's purpose is supervision, not sanitisation. A refusal is an
//     event staff can see and count; a strip is invisible to everyone.
//
// # WHAT THIS DELIBERATELY DOES NOT DO
//
// It is not an adversarial-proof filter and must not be sold as one. A sender
// determined to leak a number can spell it in words, split it across two
// messages, or pad it past the length check. The real control on this thread
// is that a staff member reads it; this filter stops the casual exchange that
// supervision would otherwise have to catch by eye every time.
package moderation

import (
	"regexp"
	"strings"
	"unicode"
)

// ContactKind names what a message was refused for. Empty means nothing found.
type ContactKind string

const (
	ContactNone  ContactKind = ""
	ContactPhone ContactKind = "phone"
	ContactEmail ContactKind = "email"
	ContactBoth  ContactKind = "both"
)

// ContactFinding is the result of scanning one message body.
type ContactFinding struct {
	// Kind is what was found — phone, email, or both.
	Kind ContactKind
	// Count is how many distinct matches were found, used by the supervision
	// record to distinguish a slip from a deliberate, repeated attempt.
	Count int
	// Redacted is the body with every match replaced by a marker. It is what
	// gets STORED for staff: it preserves the surrounding wording (which is
	// what tells a supervisor whether this was coercion or a misunderstanding)
	// while ensuring the attempt log never becomes a directory of the very
	// numbers the block exists to keep out of the thread.
	Redacted string
}

// Blocked reports whether the message must be refused.
func (f ContactFinding) Blocked() bool { return f.Kind != ContactNone }

// redactionMarker replaces a match in the stored supervision record.
const redactionMarker = "•••"

// maxJoinerRun is how many consecutive separator characters may sit between
// two digits and still be read as one number. Three covers every human way of
// writing a number ("0770 - 123 - 4567" is the widest at three) without
// letting two unrelated figures on either side of a paragraph break merge into
// a false positive.
const maxJoinerRun = 3

// emailRE matches a conventional address. Deliberately ordinary: the exotic
// forms RFC 5322 permits are not what someone types to arrange a call.
var emailRE = regexp.MustCompile(`[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}`)

// asciiDigit folds the three digit sets an Iraqi keyboard can produce into one
// ASCII digit. Latin, Arabic-Indic (U+0660–0669, the Arabic keyboard) and
// extended Arabic-Indic (U+06F0–06F9, the Persian/Kurdish keyboard) all render
// as a number a human reads identically, so a filter that understands only the
// first is bypassed by switching layout — and is worse than no filter, because
// it looks like protection.
func asciiDigit(r rune) (rune, bool) {
	switch {
	case r >= '0' && r <= '9':
		return r, true
	case r >= 0x0660 && r <= 0x0669:
		return '0' + (r - 0x0660), true
	case r >= 0x06F0 && r <= 0x06F9:
		return '0' + (r - 0x06F0), true
	}
	return 0, false
}

// isJoiner reports whether a rune may sit between two digits without ending
// the number.
//
// The Unicode classes matter more than the ASCII punctuation: \p{Z} catches
// the non-breaking space and \p{Cf} the zero-width joiner and bidi marks that
// internal/auth/phone.go already had to learn about, because Arabic-mode input
// genuinely carries them. Here they are also the cheapest possible evasion —
// a zero-width joiner mid-number is invisible to the reader and, without this,
// invisible to the filter.
func isJoiner(r rune) bool {
	switch r {
	case ' ', '\t', '\n', '\r', '-', '.', ',', '/', '\\', '(', ')', '_', '*', '+':
		return true
	case '،', '–', '—', '‐', '‑': // Arabic comma and the Unicode dashes
		return true
	}
	return unicode.IsSpace(r) || unicode.In(r, unicode.Z, unicode.Cf)
}

// isPhoneShape reports whether a run of digits is an Iraqi mobile number.
//
// The four accepted lengths are the four ways internal/auth/phone.go already
// accepts the same number on the login screen, and each is anchored on the
// mobile marker — "07…" nationally, "9647…" with the dial code. That anchor is
// what keeps donation amounts out: an amount never carries a leading zero, so
// no 11-digit amount can begin "07", and a bare 10-digit figure (which
// NormalizePhone would happily accept as a local number) is left alone here
// precisely because it is indistinguishable from money.
//
// The match is against the WHOLE run, never a substring of it. Searching
// inside a longer run would fire on "07-01-2026 07-05-2026", where eleven of
// the sixteen digits happen to line up.
func isPhoneShape(digits string) bool {
	switch len(digits) {
	case 11:
		return strings.HasPrefix(digits, "07")
	case 13:
		return strings.HasPrefix(digits, "9647")
	case 15:
		return strings.HasPrefix(digits, "009647")
	}
	return false
}

// span is a half-open rune range [start, end) of the original body.
type span struct{ start, end int }

// ScanContact examines one message body for contact details.
//
// It never returns an error: a body it cannot make sense of is simply a body
// with nothing in it, and a filter that could fail open on a parse error would
// be a hole in exactly the direction that matters.
func ScanContact(body string) ContactFinding {
	if strings.TrimSpace(body) == "" {
		return ContactFinding{}
	}
	runes := []rune(body)

	phones := findPhoneSpans(runes)
	emails := findEmailSpans(runes)

	f := ContactFinding{Count: len(phones) + len(emails)}
	switch {
	case len(phones) > 0 && len(emails) > 0:
		f.Kind = ContactBoth
	case len(phones) > 0:
		f.Kind = ContactPhone
	case len(emails) > 0:
		f.Kind = ContactEmail
	default:
		return ContactFinding{}
	}
	f.Redacted = redact(runes, append(phones, emails...))
	return f
}

// findPhoneSpans walks the body once, growing a candidate number across
// separator characters and testing each completed run against isPhoneShape.
func findPhoneSpans(runes []rune) []span {
	var out []span
	i := 0
	for i < len(runes) {
		if _, ok := asciiDigit(runes[i]); !ok {
			i++
			continue
		}
		// Start of a run. Extend across digits and short joiner gaps.
		start, end := i, i
		var digits strings.Builder
		j := i
		for j < len(runes) {
			if d, ok := asciiDigit(runes[j]); ok {
				digits.WriteRune(d)
				end = j + 1
				j++
				continue
			}
			// Measure the joiner gap; a gap that is too long, or that is
			// not a joiner at all, ends the run.
			gap := 0
			for j+gap < len(runes) && isJoiner(runes[j+gap]) {
				gap++
			}
			if gap == 0 || gap > maxJoinerRun {
				break
			}
			if j+gap >= len(runes) {
				break
			}
			if _, ok := asciiDigit(runes[j+gap]); !ok {
				break
			}
			j += gap
		}
		if isPhoneShape(digits.String()) {
			out = append(out, span{start, end})
		}
		i = end
		if i <= start {
			i = start + 1
		}
	}
	return out
}

// findEmailSpans matches addresses both as written and with the whitespace
// around "@" and "." removed, so "ahmad @ example . com" is caught alongside
// the plain form. Only whitespace ADJACENT to those two characters is dropped:
// collapsing everything would glue ordinary prose into something the address
// pattern matches.
func findEmailSpans(runes []rune) []span {
	out := matchEmails(runes, identityMap(len(runes)))
	compact, idx := compactAroundEmailPunctuation(runes)
	if len(compact) != len(runes) {
		out = append(out, matchEmails(compact, idx)...)
	}
	return out
}

// identityMap maps each rune position to itself.
func identityMap(n int) []int {
	m := make([]int, n)
	for i := range m {
		m[i] = i
	}
	return m
}

// matchEmails runs the address pattern over runes and translates every match
// back to rune spans of the ORIGINAL body via idx.
func matchEmails(runes []rune, idx []int) []span {
	s := string(runes)
	// Byte offset of each rune, so regex byte matches become rune indices.
	runeAt := make([]int, 0, len(runes)+1)
	b := 0
	for _, r := range runes {
		runeAt = append(runeAt, b)
		b += len(string(r))
	}
	runeAt = append(runeAt, b)

	byteToRune := func(off int) int {
		for k, at := range runeAt {
			if at >= off {
				return k
			}
		}
		return len(runes)
	}

	var out []span
	for _, m := range emailRE.FindAllStringIndex(s, -1) {
		lo, hi := byteToRune(m[0]), byteToRune(m[1])
		if lo >= len(idx) {
			continue
		}
		end := hi
		if end > len(idx) {
			end = len(idx)
		}
		origLo := idx[lo]
		origHi := origLo + 1
		if end > 0 {
			origHi = idx[end-1] + 1
		}
		out = append(out, span{origLo, origHi})
	}
	return out
}

// compactAroundEmailPunctuation removes whitespace runs that touch "@" or ".",
// returning the compacted runes and, for each, its index in the original.
func compactAroundEmailPunctuation(runes []rune) ([]rune, []int) {
	out := make([]rune, 0, len(runes))
	idx := make([]int, 0, len(runes))
	i := 0
	for i < len(runes) {
		if !isSpaceish(runes[i]) {
			out = append(out, runes[i])
			idx = append(idx, i)
			i++
			continue
		}
		j := i
		for j < len(runes) && isSpaceish(runes[j]) {
			j++
		}
		var prev, next rune
		if len(out) > 0 {
			prev = out[len(out)-1]
		}
		if j < len(runes) {
			next = runes[j]
		}
		if prev == '@' || prev == '.' || next == '@' || next == '.' {
			i = j // drop it entirely
			continue
		}
		out = append(out, ' ')
		idx = append(idx, i)
		i = j
	}
	return out, idx
}

func isSpaceish(r rune) bool {
	return unicode.IsSpace(r) || unicode.In(r, unicode.Z, unicode.Cf)
}

// redact replaces every span with the marker, leaving the rest of the wording
// intact for the supervision record.
func redact(runes []rune, spans []span) string {
	if len(spans) == 0 {
		return string(runes)
	}
	hidden := make([]bool, len(runes))
	for _, sp := range spans {
		for i := sp.start; i < sp.end && i < len(runes); i++ {
			if i >= 0 {
				hidden[i] = true
			}
		}
	}
	var b strings.Builder
	i := 0
	for i < len(runes) {
		if !hidden[i] {
			b.WriteRune(runes[i])
			i++
			continue
		}
		b.WriteString(redactionMarker)
		for i < len(runes) && hidden[i] {
			i++
		}
	}
	return b.String()
}
