package notify

import (
	"context"
	"errors"
	"log"
)

// deviceTarget is one active device + the language preference its owner
// picked in-app. Phase 27.3 — sendPush uses this to deliver each device
// its own preferred-language title/body, rather than always EN.
type deviceTarget struct {
	Token      string
	LocaleCode string // "en" | "ar" | "ckb" | "kmr" | "" (= use EN)
}

// sendPush is the fire-and-forget hook called by Send() after writing the
// in-DB notification. Looks up the user's active devices (one or more)
// and pushes each its preferred-language title/body. Failures (including
// "FCM not configured") are logged but not returned.
//
// Phase 27.3 — takes the full LocalizedMessage so it can pick per-device
// text. Previously this took raw EN strings and every push was in
// English regardless of the volunteer's in-app language.
func (n *Notifier) sendPush(ctx context.Context, userID int64, m LocalizedMessage) error {
	devices, err := n.activeDevicesFor(ctx, userID)
	if err != nil {
		log.Printf("[notify:push] tokens lookup user=%d: %v", userID, err)
		return err
	}
	if len(devices) == 0 {
		return nil
	}

	if n.fcm == nil {
		log.Printf("[notify:push] FCM not configured; in-DB notification written for user=%d (%d tokens skipped)", userID, len(devices))
		return nil
	}
	for _, d := range devices {
		title, body := pickLocalizedText(m, d.LocaleCode)
		r := n.fcm.sendOne(ctx, d.Token, title, body, "")
		if !r.OK {
			log.Printf("[notify:push] send to user=%d (locale=%q) failed: %s",
				userID, d.LocaleCode, r.Error)
			// Phase 27.4 — auto-deactivate tokens FCM reports as dead so
			// the next broadcast doesn't waste a round trip on them.
			if looksLikeDeadToken(r.Error) {
				n.deactivateToken(ctx, d.Token)
				log.Printf("[notify:push] deactivated dead token for user=%d", userID)
			}
		}
	}
	return nil
}

// pickLocalizedText resolves a LocalizedMessage + locale code into the
// pair of strings the FCM payload needs. Falls back to EN whenever the
// requested locale's slot is empty (i.e. a template that hasn't been
// translated for that language yet) or when the locale code itself is
// unknown — so a missing translation degrades to EN rather than blank.
func pickLocalizedText(m LocalizedMessage, locale string) (title, body string) {
	switch locale {
	case "ar":
		title, body = m.Title.Ar, m.Body.Ar
	case "ckb":
		title, body = m.Title.Ckb, m.Body.Ckb
	case "kmr":
		title, body = m.Title.Kmr, m.Body.Kmr
	}
	if title == "" {
		title = m.Title.En
	}
	if body == "" {
		body = m.Body.En
	}
	return title, body
}

// SendPushDirect is exposed for the admin compose endpoint. It expands to a
// list of device tokens using the first set target in this order:
//   • deviceToken    → single token
//   • userID         → all active tokens of that user
//   • roleID         → all active tokens of every user with that role
//   • allUsers=true  → every active token in the system (broadcast)
// Returns one SendResult per delivery attempt.
//
// Returns errFCMDisabled if no Firebase credentials are configured.
func (n *Notifier) SendPushDirect(ctx context.Context, deviceToken string, userID int64,
	roleID int, allUsers bool, title, body, imageURL string) ([]SendResult, error) {
	if n.fcm == nil {
		return nil, errFCMDisabled
	}

	var tokens []string
	switch {
	case deviceToken != "":
		tokens = []string{deviceToken}
	case userID > 0:
		t, err := n.activeTokensFor(ctx, userID)
		if err != nil {
			return nil, err
		}
		if len(t) == 0 {
			return []SendResult{}, errors.New("no active device tokens for that user")
		}
		tokens = t
	case roleID > 0:
		t, err := n.activeTokensForRole(ctx, roleID)
		if err != nil {
			return nil, err
		}
		if len(t) == 0 {
			return []SendResult{}, errors.New("no active device tokens for that role")
		}
		tokens = t
	case allUsers:
		t, err := n.activeTokensAll(ctx)
		if err != nil {
			return nil, err
		}
		if len(t) == 0 {
			return []SendResult{}, errors.New("no active device tokens in the system")
		}
		tokens = t
	default:
		return nil, errors.New("supply device_token, user_id, role_id, or all_users")
	}

	results := make([]SendResult, 0, len(tokens))
	for _, t := range tokens {
		r := n.fcm.sendOne(ctx, t, title, body, imageURL)
		results = append(results, r)
		// Phase 27.4 — same dead-token cleanup as the automatic per-event
		// path. The admin compose endpoint can re-broadcast frequently
		// (testing, scheduled blasts), so this is where stale tokens
		// pile up fastest.
		if !r.OK && looksLikeDeadToken(r.Error) {
			n.deactivateToken(ctx, t)
		}
	}
	return results, nil
}

// FCMConfigured reports whether a Firebase service account is loaded.
func (n *Notifier) FCMConfigured() bool { return n.fcm != nil }

// activeTokensAll returns every active device token in the system across all
// users and roles. Used for the "Broadcast" target on the admin compose page.
func (n *Notifier) activeTokensAll(ctx context.Context) ([]string, error) {
	rows, err := n.Pool.Query(ctx,
		`SELECT udt.device_token
		   FROM user_device_tokens udt
		   JOIN users u ON u.id = udt.user_id
		  WHERE udt.is_active = 1
		    AND u.active     = 1`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err == nil && t != "" {
			out = append(out, t)
		}
	}
	return out, rows.Err()
}

// activeTokensForRole returns every active device token belonging to a user
// with the given role_id. Used by the admin compose endpoint for broadcast
// pushes ("notify all donors / volunteers / beneficiaries").
func (n *Notifier) activeTokensForRole(ctx context.Context, roleID int) ([]string, error) {
	if roleID <= 0 {
		return nil, nil
	}
	rows, err := n.Pool.Query(ctx,
		`SELECT udt.device_token
		   FROM user_device_tokens udt
		   JOIN users u ON u.id = udt.user_id
		  WHERE u.role_id = $1
		    AND u.active   = 1
		    AND udt.is_active = 1`, roleID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err == nil && t != "" {
			out = append(out, t)
		}
	}
	return out, rows.Err()
}

// activeDevicesFor returns the active devices for a user, paired with the
// locale_code each device registered with. Used by sendPush so every
// device gets its owner's preferred-language title/body. A NULL
// locale_code in the DB becomes an empty string in the result —
// pickLocalizedText then falls back to EN.
func (n *Notifier) activeDevicesFor(ctx context.Context, userID int64) ([]deviceTarget, error) {
	if userID <= 0 {
		return nil, nil
	}
	rows, err := n.Pool.Query(ctx,
		`SELECT device_token, COALESCE(locale_code, '')
		   FROM user_device_tokens
		  WHERE user_id = $1 AND is_active = 1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []deviceTarget{}
	for rows.Next() {
		var d deviceTarget
		if err := rows.Scan(&d.Token, &d.LocaleCode); err == nil && d.Token != "" {
			out = append(out, d)
		}
	}
	return out, rows.Err()
}

// activeTokensFor returns the device tokens marked active for a user.
// (Kept for the admin compose endpoint which sends a single explicit
// title/body and doesn't need the per-device locale lookup.)
func (n *Notifier) activeTokensFor(ctx context.Context, userID int64) ([]string, error) {
	if userID <= 0 {
		return nil, nil
	}
	rows, err := n.Pool.Query(ctx,
		`SELECT device_token FROM user_device_tokens
		  WHERE user_id = $1 AND is_active = 1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err == nil && t != "" {
			out = append(out, t)
		}
	}
	return out, rows.Err()
}

// ErrFCMDisabled is the public form of the internal "not configured" sentinel
// so callers can do errors.Is checks.
var ErrFCMDisabled error = errFCMDisabled
