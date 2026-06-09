package notify

import (
	"context"
	"errors"
	"strings"
)

// RegisterDevice upserts a (user, device_token) row in user_device_tokens
// and ensures is_active=1 + last_seen_at=NOW(). roleID may be 0 ("unknown").
// platform: "android" | "ios" | "web" | "" (any non-empty short string is fine).
//
// Phase 27.3 — `localeCode` is the volunteer/donor/beneficiary's preferred
// app language ("en" | "ar" | "ckb" | "kmr"). Stored on the device row so
// sendPush can choose the matching Title/Body from a LocalizedMessage
// without re-querying users. An empty string means "use the default" and
// is stored as NULL; sendPush will then fall back to EN.
func (n *Notifier) RegisterDevice(
	ctx context.Context,
	userID int64,
	roleID int,
	deviceToken, platform, deviceID, appVersion, localeCode string,
) error {
	if userID <= 0 {
		return errors.New("invalid userID")
	}
	deviceToken = strings.TrimSpace(deviceToken)
	if deviceToken == "" {
		return errors.New("missing device_token")
	}
	if len(deviceToken) > 512 {
		return errors.New("device_token too long")
	}

	var roleArg any
	if roleID > 0 {
		roleArg = roleID
	}
	var platformArg any
	if p := strings.TrimSpace(platform); p != "" {
		if len(p) > 32 {
			p = p[:32]
		}
		platformArg = p
	}
	var deviceArg any
	if d := strings.TrimSpace(deviceID); d != "" {
		if len(d) > 128 {
			d = d[:128]
		}
		deviceArg = d
	}
	var verArg any
	if v := strings.TrimSpace(appVersion); v != "" {
		if len(v) > 64 {
			v = v[:64]
		}
		verArg = v
	}
	// Normalize the locale code: lowercase, trim, accept only the 4
	// supported languages. Anything else (or empty) becomes NULL → EN
	// fallback at push time.
	var localeArg any
	if l := strings.ToLower(strings.TrimSpace(localeCode)); l != "" {
		switch l {
		case "en", "ar", "ckb", "kmr":
			localeArg = l
		}
	}

	_, err := n.Pool.Exec(ctx, `
		INSERT INTO user_device_tokens
		   (user_id, role_id, device_token, platform, device_id, app_version, locale_code,
		    is_active, created_at, updated_at, last_seen_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 1, NOW(), NOW(), NOW())
		ON CONFLICT (user_id, device_token) DO UPDATE
		   SET role_id      = COALESCE(EXCLUDED.role_id, user_device_tokens.role_id),
		       platform     = COALESCE(EXCLUDED.platform, user_device_tokens.platform),
		       device_id    = COALESCE(EXCLUDED.device_id, user_device_tokens.device_id),
		       app_version  = COALESCE(EXCLUDED.app_version, user_device_tokens.app_version),
		       locale_code  = COALESCE(EXCLUDED.locale_code, user_device_tokens.locale_code),
		       is_active    = 1,
		       updated_at   = NOW(),
		       last_seen_at = NOW()`,
		userID, roleArg, deviceToken, platformArg, deviceArg, verArg, localeArg,
	)
	return err
}

// deactivateToken marks ANY (user_id, device_token) match inactive. Used
// by the push pipeline to clean up dead tokens automatically when FCM
// reports them as UNREGISTERED / INVALID_ARGUMENT — so the next
// broadcast doesn't waste another round trip on the same dead token,
// and the admin's /push page sees an accurate active count.
//
// Unlike UnregisterDevice this doesn't require knowing the user — we
// look up by token alone since the token is unique across the table.
func (n *Notifier) deactivateToken(ctx context.Context, deviceToken string) {
	if strings.TrimSpace(deviceToken) == "" {
		return
	}
	_, _ = n.Pool.Exec(ctx,
		`UPDATE user_device_tokens
		    SET is_active = 0, updated_at = NOW()
		  WHERE device_token = $1 AND is_active = 1`,
		deviceToken,
	)
}

// looksLikeDeadToken returns true if an FCM error message indicates the
// token will never deliver again (versus a transient network issue). We
// check for the canonical error codes FCM returns in the JSON body —
// substring match is intentional since the message wraps a structured
// error inside an HTTP 400 body.
func looksLikeDeadToken(errMsg string) bool {
	if errMsg == "" {
		return false
	}
	// FCM HTTP v1 error codes that mean "this token is permanently dead":
	//   UNREGISTERED       — app uninstalled / token revoked
	//   NOT_REGISTERED     — legacy variant
	//   INVALID_ARGUMENT   — malformed / wrong project
	//   SENDER_ID_MISMATCH — token belongs to a different project
	for _, sentinel := range []string{
		"UNREGISTERED",
		"NOT_REGISTERED",
		"INVALID_ARGUMENT",
		"SENDER_ID_MISMATCH",
	} {
		if strings.Contains(errMsg, sentinel) {
			return true
		}
	}
	return false
}

// ActiveDeviceCount returns the number of currently-active device tokens
// in the system. Surfaced to the admin SPA's /push page so the admin
// knows what their broadcast target is before they click Send.
func (n *Notifier) ActiveDeviceCount(ctx context.Context) (int, error) {
	var count int
	err := n.Pool.QueryRow(ctx,
		`SELECT COUNT(*)
		   FROM user_device_tokens t
		   JOIN users u ON u.id = t.user_id
		  WHERE t.is_active = 1 AND u.active = 1`,
	).Scan(&count)
	return count, err
}

// UnregisterDevice marks a (user, device_token) row inactive. Returns true
// when at least one row was updated.
func (n *Notifier) UnregisterDevice(ctx context.Context, userID int64, deviceToken string) (bool, error) {
	if userID <= 0 {
		return false, errors.New("invalid userID")
	}
	deviceToken = strings.TrimSpace(deviceToken)
	if deviceToken == "" {
		return false, errors.New("missing device_token")
	}
	res, err := n.Pool.Exec(ctx,
		`UPDATE user_device_tokens
		    SET is_active = 0, updated_at = NOW()
		  WHERE user_id = $1 AND device_token = $2`,
		userID, deviceToken,
	)
	if err != nil {
		return false, err
	}
	return res.RowsAffected() > 0, nil
}
