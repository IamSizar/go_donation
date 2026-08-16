// voice.go — M9's third reminder channel: "تنبيه صوتي داخل التطبيق عند
// توفره" — an automated voice alert, delivered when a provider is available.
//
// # WHAT THIS IS, AND WHAT IT IS DELIBERATELY NOT
//
// This is the SEAM ONLY. There is no provider in it, no HTTP client, no SDK and
// no new dependency, because there is no voice account to point one at — and a
// provider written against a service nobody has bought is a guess that will be
// wrong in the details that matter (audio format, language codes, retry
// semantics, per-call cost). What exists here is the interface the sweep calls
// and the wiring that carries it, so adding a real provider is one small type
// plus one line in main.go.
//
// # THE MISTAKE THIS FILE REFUSES TO REPEAT
//
// The SMS leg of these same reminders has never worked in any environment, and
// nobody noticed for a reason worth writing down: main.go's SMS closure returns
// `nil` — success — when OTPIQ is unconfigured. Every caller was told the
// message went out. internal/config's own SMTPConfig comment already states the
// rule that was broken there: "none of them may report success for a message
// that never left."
//
// So an unconfigured voice channel returns ErrVoiceNotConfigured, never nil.
// The sweep logs it once and carries on; it does not pretend to have called
// anybody.
package notify

import (
	"context"
	"errors"
)

// ErrVoiceNotConfigured is returned when no voice provider is wired. It is a
// normal, expected condition in every environment today — callers should treat
// it as "this channel is off", not as a failure to report loudly.
var ErrVoiceNotConfigured = errors.New("voice reminders are not configured")

// VoiceCaller places one automated reminder call.
//
// Implementations must be safe for concurrent use and must respect ctx: the
// reminder sweep runs under a timeout, and a provider that blocks past it would
// stall every remaining reminder behind it.
//
// phone is the canonical digits-only form produced by auth.NormalizePhone
// (e.g. "9647508582031") — the same shape the SMS leg receives, so a provider
// never has to re-parse whatever a user typed.
//
// message is the plain-text script to speak. It carries no markup and no SSML:
// what a given provider needs is unknowable until one is chosen, and inventing
// a format now would be a guess baked into every call site.
type VoiceCaller interface {
	PlaceCall(ctx context.Context, phone, message string) error
}

// VoiceCallerFunc adapts a plain function to VoiceCaller, so a provider that is
// genuinely one HTTP call can be wired in main.go without declaring a type —
// the same shape the SMS sender already uses.
type VoiceCallerFunc func(ctx context.Context, phone, message string) error

// PlaceCall implements VoiceCaller.
func (f VoiceCallerFunc) PlaceCall(ctx context.Context, phone, message string) error {
	if f == nil {
		return ErrVoiceNotConfigured
	}
	return f(ctx, phone, message)
}

// VoiceConfigured reports whether a usable provider is wired. Nil-safe, and it
// handles the interface-holding-a-nil-function case that a plain `!= nil` check
// would get wrong.
func VoiceConfigured(v VoiceCaller) bool {
	switch t := v.(type) {
	case nil:
		return false
	case VoiceCallerFunc:
		return t != nil
	default:
		return true
	}
}

// PlaceVoiceCall is the nil-safe entry point every caller should use.
//
// It returns ErrVoiceNotConfigured — never nil — when nothing is wired, which
// is the whole point of this file. Empty phone numbers are refused for the same
// reason: a provider asked to dial "" has not placed a call, and saying it did
// would be the same lie in a different place.
func PlaceVoiceCall(ctx context.Context, v VoiceCaller, phone, message string) error {
	if !VoiceConfigured(v) {
		return ErrVoiceNotConfigured
	}
	if phone == "" {
		return errors.New("voice reminder: no phone number for this recipient")
	}
	return v.PlaceCall(ctx, phone, message)
}
