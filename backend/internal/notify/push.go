package notify

import (
	"context"
	"errors"
	"log"
	"slices"
	"strconv"
	"strings"
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
// "FCM not configured") are logged; a failed device lookup is also returned,
// which Send ignores.
//
// Phase 27.3 — takes the full LocalizedMessage so it can pick per-device
// text. Previously this took raw EN strings and every push was in
// English regardless of the volunteer's in-app language.
//
// OPOS #26443 — this is where the push decision is made, so it is where a
// guest's chat pushes are withheld (shouldWithholdChatPush).
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
	// Checked once per send, not per device, and only after the cheap exits
	// above, so a user with no device or a server without FCM never pays for
	// the lookup.
	if n.shouldWithholdChatPush(ctx, userID, m.Type) {
		return nil
	}
	for _, d := range devices {
		title, body := pickLocalizedText(m, d.LocaleCode)
		r := n.fcm.sendOne(ctx, d.Token, title, body, "", routingData(m))
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

// shouldWithholdChatPush reports whether a push of notificationType to userID
// must be withheld because the recipient is a guest (OPOS #26443).
//
// Guests must not read chats. Several chat notifications carry the message
// itself as their body (an 80-character preview), and List already hides
// those rows from a guest (OPOS #26424). Without this gate, the push would
// still put that preview on a grandfathered guest's lock screen.
//
// Only chat types are gated, using chatNotificationTypes, the same list List
// filters on, so the in-app list and the phone always agree. For any other
// type it returns false without querying: guests keep broadcasts and
// support-ticket pushes, and a non-chat push costs nothing extra.
//
// For a chat type it makes one query. Guest status comes from users.is_guest,
// the column the token resolver reads on every request, so an upgraded account
// gets chat pushes again straight away.
//
// It fails closed. If the lookup errors, including a missing user row, the
// chat push is withheld and the error is logged. Send has already written the
// in-app row, so a withheld push costs a member little; a pushed preview to a
// guest is the leak this exists to stop.
func (n *Notifier) shouldWithholdChatPush(ctx context.Context, userID int64, notificationType string) bool {
	if !slices.Contains(chatNotificationTypes, notificationType) {
		return false
	}
	// COALESCE matches users.go. The column is NOT NULL (migration 064), but a
	// NULL must read as a member, never as a failure that mutes their chats.
	var isGuest bool
	if err := n.Pool.QueryRow(ctx,
		`SELECT COALESCE(is_guest, FALSE) FROM users WHERE id = $1`, userID,
	).Scan(&isGuest); err != nil {
		log.Printf("[notify:push] guest lookup user=%d type=%s failed; chat push withheld: %v",
			userID, notificationType, err)
		return true
	}
	if isGuest {
		log.Printf("[notify:push] chat push withheld from guest user=%d type=%s", userID, notificationType)
	}
	return isGuest
}

// routingData is the FCM `data` payload for one notification: what the app
// needs to open the right screen when the user taps the banner.
//
// It rides alongside the notification block (see buildSendPayload) rather than
// replacing it, so the OS still draws the alert on its own. Keys match the
// columns app_notifications stores, so the phone and the in-app list describe
// the same event. Values must be strings — FCM rejects any other JSON type in
// data. Empty fields are dropped by buildSendPayload.
func routingData(m LocalizedMessage) map[string]string {
	d := map[string]string{
		"notification_type":   m.Type,
		"related_entity_type": m.RelatedEntityType,
		"action_url":          m.ActionURL,
	}
	if m.RelatedEntityID > 0 {
		d["related_entity_id"] = strconv.FormatInt(m.RelatedEntityID, 10)
	}
	return d
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
//   - deviceToken    → single token
//   - userID         → all active tokens of that user
//   - roleID         → all active tokens of every user with that role
//   - packageSlug    → every user on that marriage subscription package (#13)
//   - allUsers=true  → every active token in the system (broadcast)
//
// Returns one SendResult per delivery attempt.
//
// Returns errFCMDisabled if no Firebase credentials are configured.
func (n *Notifier) SendPushDirect(ctx context.Context, deviceToken string, userID int64,
	roleID int, packageSlug string, allUsers bool, title, body, imageURL string) ([]SendResult, error) {
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
	case strings.TrimSpace(packageSlug) != "":
		t, err := n.activeTokensForPackage(ctx, packageSlug)
		if err != nil {
			return nil, err
		}
		if len(t) == 0 {
			return []SendResult{}, errors.New("no active device tokens on that package")
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
		return nil, errors.New("supply device_token, user_id, role_id, package, or all_users")
	}

	results := make([]SendResult, 0, len(tokens))
	for _, t := range tokens {
		// The admin compose endpoint sends free text with no related entity,
		// so there is nothing to route to: notification block only.
		r := n.fcm.sendOne(ctx, t, title, body, imageURL, nil)
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

// activeTokensForPackage returns every active device token belonging to a user
// whose marriage profile sits on the given subscription package (#13).
//
// Mirrors BroadcastToPackage's audience exactly — active user, active
// profile, DISTINCT so a second profile row can't double-send — so the push
// and in-app channels always reach the same people.
func (n *Notifier) activeTokensForPackage(ctx context.Context, packageSlug string) ([]string, error) {
	packageSlug = strings.TrimSpace(packageSlug)
	if packageSlug == "" {
		return nil, nil
	}
	rows, err := n.Pool.Query(ctx,
		`SELECT DISTINCT udt.device_token
		   FROM user_device_tokens udt
		   JOIN users u ON u.id = udt.user_id
		   JOIN marriage_profiles mp ON mp.user_id = u.id
		  WHERE u.active = 1
		    AND udt.is_active = 1
		    AND mp.status = 'active'
		    AND mp.subscription_status = $1`, packageSlug)
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
