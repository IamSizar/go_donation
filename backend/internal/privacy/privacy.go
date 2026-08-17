// Package privacy turns the user's stored privacy choices into something the
// API actually obeys.
//
// WHY THIS PACKAGE EXISTS (K8)
// `user_profiles.field_privacy` (migration 040, catalogue in migration 083)
// has held each user's list of "fields other people may not see" since the
// Privacy Settings screen shipped. It had exactly three touch points in the
// whole backend, all of them the OWNER looking at their OWN row: the getter,
// the setter, and the column echoed back in the owner's account payload.
// Nothing consulted it when a profile was served to somebody else. Chat
// headers, sponsorship lists and public case cards printed real names and
// phone numbers no matter what the user had switched off — the screen was a
// row of switches wired to nothing.
//
// The same was true of the display-name choice (`display_name_mode` /
// `alias_name`, migration 073): a user could pick "show my alias instead of my
// real name" and every screen kept showing the real one.
//
// WHAT THIS PACKAGE DOES
// It is the single place the policy is written down, so the serving code can
// only get it right:
//
//	set, err := store.Load(ctx, ownerIDs)   // ONE query for the whole page
//	seen := set.AsSeenBy(viewerID)          // the person being served
//	name  := seen.Name(ownerID, rawName)    // alias / real / nil
//	phone := seen.Field(ownerID, privacy.FieldPhone, rawPhone)
//
// Deliberate boundaries, so nobody has to guess what is covered:
//
//   - A user is NEVER masked from themselves. AsSeenBy carries the viewer's
//     id and short-circuits on it. Pass 0 for an unauthenticated viewer.
//   - This is for USER-FACING paths only. Staff dashboards are governed by a
//     different, already-implemented mechanism (the `sensitive_data`
//     permission, admin_detail.go), so admin queries must not use this.
//   - For a SIGNED-IN reader, only choices the user actually SAVED are
//     enforced. The catalogue's `default_hidden` column is still NOT applied to
//     users who never opened the screen: honouring it there would retroactively
//     hide every user's phone number app-wide, which is a product decision, not
//     a bug fix. See the K8 row in VERIFICATION_REPORT.md.
//   - For an ANONYMOUS reader (viewerID 0), `default_hidden` IS applied on top
//     of the saved choices. The two readers are asking different questions, and
//     the second one was answered by publishing an applicant's phone and street
//     address to the open internet. See hiddenFor for the full reasoning.
package privacy

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ─── Field keys ─────────────────────────────────────────────────────────
//
// These mirror privacy_field_options.field_key (migration 083). The catalogue
// is data-driven — staff can add a row and the app renders a new switch — so
// this list is not exhaustive by design. Any key can be passed to Field();
// the constants exist only so call sites can't typo the common ones.

const (
	FieldFullName       = "full_name"
	FieldPhone          = "phone"
	FieldGender         = "gender"
	FieldAddress        = "address"
	FieldDateOfBirth    = "date_of_birth"
	FieldProfilePicture = "profile_picture"
	FieldAge            = "age"
	FieldEducationLevel = "education_level"
	FieldOccupation     = "occupation"
	FieldGovernorate    = "governorate"
)

// displayModeAlias is the value display_name_mode takes when the user asked
// to be shown under an alias (migration 073's CHECK constraint allows only
// this and "real").
const displayModeAlias = "alias"

// ─── Settings ───────────────────────────────────────────────────────────

// Settings is one user's saved privacy choices. The zero value hides nothing,
// which is the correct reading of "this user has no row / no preferences".
type Settings struct {
	hidden          map[string]bool
	displayNameMode string
	aliasName       string
}

// Hides reports whether the user switched this field off for other people.
func (s Settings) Hides(key string) bool {
	return s.hidden[key]
}

// alias returns the stand-in name the user chose, or "" if they didn't.
func (s Settings) alias() string {
	if s.displayNameMode == displayModeAlias && s.aliasName != "" {
		return s.aliasName
	}
	return ""
}

// ─── Set: one page's worth of owners ────────────────────────────────────

// Set holds the settings of every user whose data is about to be serialised,
// keyed by user id. Missing ids simply have no preferences.
type Set map[int64]Settings

// AsSeenBy binds the set to the person the response is being written for.
// viewerID 0 means "nobody is signed in", which matches no owner and so masks
// everything the owners asked to hide.
func (set Set) AsSeenBy(viewerID int64) Viewer {
	return Viewer{set: set, viewerID: viewerID}
}

// Viewer applies a Set from one particular reader's point of view.
type Viewer struct {
	set      Set
	viewerID int64
	// publicDefaults is the catalogue's `default_hidden` map, loaded only when
	// viewerID is 0. See hiddenFor.
	publicDefaults map[string]bool
}

// hiddenFor decides whether one owner's field is withheld from this viewer.
//
// A saved choice always wins. What changes for an anonymous reader is the
// answer when there is no saved choice, because "no choice" is not the same
// question in the two cases:
//
//   - Signed in: the reader is a known person inside the app, and showing a
//     field its owner never objected to is the behaviour the app was built on.
//   - Signed out: the reader is the open internet. A public beneficiary case
//     was serving a named applicant's phone and street address next to a
//     description of their hardship, to anyone who fetched the URL, because
//     the applicant had never opened the Privacy Settings screen.
//
// The fallback is the catalogue's own `default_hidden` — the product's stated
// intent for each field, already recorded in privacy_field_options (phone and
// address ship true). It was previously applied to nobody, since the comment
// at the top of this file rightly refused to apply it retroactively app-wide:
// that is a product decision. Applying it only to unauthenticated readers is
// the narrow half of that decision that needs no debate — nothing an existing
// user sees changes.
//
// Note this also overrides an owner who deliberately unhid a field, for
// anonymous readers only. The storage cannot tell that case apart: field_privacy
// is an array of hidden keys, so "chose to show" and "never opened the screen"
// are the same empty array. Given the two are indistinguishable, withholding is
// the direction whose failure mode is a missing phone number rather than a
// published one.
func (v Viewer) hiddenFor(ownerID int64, key string) bool {
	if v.set[ownerID].Hides(key) {
		return true
	}
	return v.viewerID == 0 && v.publicDefaults[key]
}

// Field returns val unless ownerID asked for that field to be hidden, in
// which case it returns nil. The owner always sees their own data.
func (v Viewer) Field(ownerID int64, key string, val *string) *string {
	if ownerID == 0 || ownerID == v.viewerID {
		return val
	}
	if v.hiddenFor(ownerID, key) {
		return nil
	}
	return val
}

// Name resolves the name to show for ownerID, in this order:
//
//  1. the owner is the viewer          → their real name, always
//  2. the owner chose an alias         → the alias (that is what an alias IS:
//     the stand-in they picked for exactly this situation)
//  3. the owner hid full_name          → nil
//  4. otherwise                        → the real name
//
// Returning nil rather than a placeholder keeps the decision about what to
// draw in the empty space with the client, which already has to handle a null
// name (every one of these queries LEFT JOINs user_profiles).
func (v Viewer) Name(ownerID int64, real *string) *string {
	if ownerID == 0 || ownerID == v.viewerID {
		return real
	}
	s := v.set[ownerID]
	if alias := s.alias(); alias != "" {
		out := alias
		return &out
	}
	if v.hiddenFor(ownerID, FieldFullName) {
		return nil
	}
	return real
}

// NameString is Name for the many call sites that carry a plain string rather
// than a pointer. A hidden name becomes "".
func (v Viewer) NameString(ownerID int64, real string) string {
	out := v.Name(ownerID, &real)
	if out == nil {
		return ""
	}
	return *out
}

// ─── Loading ────────────────────────────────────────────────────────────
//
// These are plain functions taking a pool rather than a Store type: every
// caller is an existing repository that already holds its own pool, so a
// second store object would be indirection with nothing in it.

// Load fetches the choices of every listed user in ONE round trip. Duplicate
// and zero ids are tolerated (callers collect them straight off a result set),
// and an empty list is a no-op rather than a query.
//
// A user with no user_profiles row simply has no entry, i.e. no preferences —
// see the package note on why absence is read as "nothing hidden" rather than
// "hide everything".
func Load(ctx context.Context, pool *pgxpool.Pool, userIDs []int64) (Set, error) {
	out := Set{}
	ids := dedupe(userIDs)
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := pool.Query(ctx,
		`SELECT user_id, COALESCE(field_privacy, '{}'), display_name_mode, alias_name
		   FROM user_profiles
		  WHERE user_id = ANY($1)`, ids)
	if err != nil {
		return nil, fmt.Errorf("load privacy settings for %d users: %w", len(ids), err)
	}
	defer rows.Close()
	for rows.Next() {
		var uid int64
		var keys []string
		var mode, alias string
		if err := rows.Scan(&uid, &keys, &mode, &alias); err != nil {
			return nil, fmt.Errorf("scan privacy settings: %w", err)
		}
		hidden := make(map[string]bool, len(keys))
		for _, k := range keys {
			if k = strings.TrimSpace(k); k != "" {
				hidden[k] = true
			}
		}
		out[uid] = Settings{
			hidden:          hidden,
			displayNameMode: strings.TrimSpace(mode),
			aliasName:       strings.TrimSpace(alias),
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read privacy settings: %w", err)
	}
	return out, nil
}

// LoadFor is the common single-page shape: collect the owner ids, load their
// settings, and bind them to the viewer — the three steps every call site
// would otherwise repeat.
//
// On error it returns a Viewer over an EMPTY set alongside the error. Callers
// must propagate the error rather than serve that Viewer: an empty set hides
// nothing, so swallowing the error would silently un-hide every field.
func LoadFor(ctx context.Context, pool *pgxpool.Pool, viewerID int64, ownerIDs []int64) (Viewer, error) {
	set, err := Load(ctx, pool, ownerIDs)
	if err != nil {
		return Set{}.AsSeenBy(viewerID), err
	}
	v := set.AsSeenBy(viewerID)
	// Only an anonymous response needs the catalogue, so a signed-in request
	// pays nothing for this. See hiddenFor.
	if viewerID == 0 {
		defaults, dErr := loadPublicDefaults(ctx, pool)
		if dErr != nil {
			// Fail closed. Returning the error costs the caller a 500 and the
			// reader an error state; carrying on without the defaults would
			// publish the very fields this lookup exists to withhold.
			return Set{}.AsSeenBy(viewerID), dErr
		}
		v.publicDefaults = defaults
	}
	return v, nil
}

// loadPublicDefaults reads the field catalogue's `default_hidden` flags.
//
// Read live rather than cached or hardcoded: privacy_field_options is an
// admin-editable table, and a stale copy would keep publishing a field after
// someone ticked it hidden. It holds ten rows.
func loadPublicDefaults(ctx context.Context, pool *pgxpool.Pool) (map[string]bool, error) {
	rows, err := pool.Query(ctx,
		`SELECT field_key FROM privacy_field_options WHERE default_hidden = TRUE`)
	if err != nil {
		return nil, fmt.Errorf("load public privacy defaults: %w", err)
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var key string
		if err := rows.Scan(&key); err != nil {
			return nil, fmt.Errorf("scan public privacy default: %w", err)
		}
		if key = strings.TrimSpace(key); key != "" {
			out[key] = true
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read public privacy defaults: %w", err)
	}
	return out, nil
}

// dedupe drops zeroes and repeats so the IN-list stays small on a page where
// the same person appears in many rows (a chat thread, a comment feed).
func dedupe(ids []int64) []int64 {
	seen := make(map[int64]bool, len(ids))
	out := make([]int64, 0, len(ids))
	for _, id := range ids {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}
