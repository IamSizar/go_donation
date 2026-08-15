// owner.go — K14: what a خطوبتي profile's OWNER may do to it.
//
// The spec asks for "a profile with edit / activate / delete-account" and there
// was nothing here to build it on: POST /api/marriage inserts a NEW row with a
// fresh profile_code, and SetFieldPrivacy was this package's only owner-scoped
// mutation. The app deliberately did not label its button "edit" for exactly
// that reason.
//
// ONE RULE RUNS THROUGH THIS WHOLE FILE: ownership is checked INSIDE the
// UPDATE, never by reading the row first and writing after. A read-then-write
// leaves a window between the two, and it makes "does this profile exist" a
// separately observable answer from "is it yours" — which turns any of these
// endpoints into a way to enumerate ids. Every statement below carries
// `AND user_id = $n`, and RowsAffected() == 0 is reported as ErrNotOwner
// whatever the reason. That is the pattern SetFieldPrivacy established
// (commit 0206ca0) and it is followed exactly.
//
// WHY THE DELETE IS A STAMP AND NOT A ROW DELETE — see DeleteOwnProfile.
package marriage

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

// ─── Errors ─────────────────────────────────────────────────────────────

// ErrNotPausable is returned when the profile is real and the caller does own
// it, but its status is not one an owner may switch off (or back on). Kept
// distinct from ErrNotOwner so the app can say "this profile is still being
// reviewed" instead of "this is not yours", which would be a lie.
var ErrNotPausable = errors.New("this engagement profile cannot be paused or resumed in its current state")

// ErrInvalidVisibility is returned for an audience value outside the three the
// column allows.
var ErrInvalidVisibility = errors.New("visibility_level must be private, employee_only or matched_summary")

// ─── تعديل — the owner's edit ───────────────────────────────────────────

// OwnerProfilePatch is the set of fields a profile's owner may change.
//
// nil means "not sent" and leaves the column alone; a pointer to an empty
// string (or to a non-positive number) means "clear this", which is how an
// optional field is un-set. Without that distinction a form could never remove
// a value it had once saved.
//
// WHAT IS DELIBERATELY ABSENT, and why:
//
//	status, subscription_status — staff decisions. An owner-writable status
//	  would be a self-approval route into the browse feed; pausing has its own
//	  narrow transition below.
//	profile_code, user_id       — identity. The code is the handle that stands
//	  in for a name.
//
// WHAT IS DELIBERATELY OUT OF SCOPE. This patch covers exactly the fields the
// Profile struct returns — the ones the owner can SEE on their own card and the
// ones search filters on. The deeper engagement-form sections (identification,
// housing, assets, health) are still changed through staff, which is what the
// app already tells users; they are not silently accepted and dropped here.
type OwnerProfilePatch struct {
	Gender           *string
	Age              *int
	City             *string
	SocialSummary    *string
	MaritalStatus    *string
	Religion         *string
	EmploymentStatus *string
	WeightKg         *int
	HeightCm         *int
	PhotoUrl         *string
	VisibilityLevel  *string
}

// UpdateOwnProfile applies the patch to a profile the caller owns.
//
// Returns ErrNotOwner when the profile does not exist, belongs to somebody
// else, or the owner has already deleted it — all three answer identically, so
// the endpoint cannot be used to probe for ids. An empty patch is a no-op
// rather than an error: a form that submits with nothing changed should not
// have to be told off for it.
func (s *Store) UpdateOwnProfile(ctx context.Context, profileID, ownerUserID int64, p OwnerProfilePatch) error {
	if profileID <= 0 || ownerUserID <= 0 {
		return errors.New("profileID and ownerUserID are required")
	}

	b := ownerSetBuilder{}
	b.text("gender", p.Gender)
	b.text("city", p.City)
	b.text("social_summary", p.SocialSummary)
	b.text("marital_status", p.MaritalStatus)
	b.text("religion", p.Religion)
	b.text("employment_status", p.EmploymentStatus)
	b.text("photo_url", p.PhotoUrl)
	b.positive("age", p.Age)
	b.positive("weight_kg", p.WeightKg)
	b.positive("height_cm", p.HeightCm)

	// The one validated field. Insert() coerces an unknown value to the
	// default because it has to produce a row from a partial registration
	// form; an explicit edit is a decision, and storing a different audience
	// than the one the user picked is a privacy failure, not a tidy-up.
	if p.VisibilityLevel != nil {
		v := strings.TrimSpace(*p.VisibilityLevel)
		switch v {
		case "private", "employee_only", "matched_summary":
			b.set("visibility_level", v)
		default:
			return fmt.Errorf("%w (got %q)", ErrInvalidVisibility, v)
		}
	}

	if len(b.sets) == 0 {
		return nil // nothing to change
	}

	tag, err := s.Pool.Exec(ctx,
		`UPDATE marriage_profiles
		    SET `+strings.Join(b.sets, ", ")+`, updated_at = CURRENT_TIMESTAMP
		  WHERE id = $`+itoa(len(b.args)+1)+`
		    AND user_id = $`+itoa(len(b.args)+2)+`
		    AND owner_deleted_at IS NULL`,
		append(b.args, profileID, ownerUserID)...)
	if err != nil {
		return fmt.Errorf("update engagement profile %d: %w", profileID, err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotOwner
	}
	return nil
}

// ownerSetBuilder assembles the SET list from only the fields that were sent.
// Column names come from this file's literals and never from a request.
type ownerSetBuilder struct {
	sets []string
	args []any
}

func (b *ownerSetBuilder) set(col string, val any) {
	b.args = append(b.args, val)
	b.sets = append(b.sets, col+" = $"+itoa(len(b.args)))
}

// text writes the trimmed string, or NULL when it is empty — every one of these
// columns is nullable, and NULL is what "the user has not filled this in" has
// always looked like, so a cleared field reads exactly like a never-filled one.
func (b *ownerSetBuilder) text(col string, val *string) {
	if val == nil {
		return
	}
	if v := strings.TrimSpace(*val); v != "" {
		b.set(col, v)
	} else {
		b.set(col, nil)
	}
}

// positive writes the number, or NULL when it is not positive. Mirrors Insert,
// which treats a non-positive age/weight/height as "not answered" rather than
// storing a zero that would then match a `age >= 1` search filter.
func (b *ownerSetBuilder) positive(col string, val *int) {
	if val == nil {
		return
	}
	if *val > 0 {
		b.set(col, *val)
	} else {
		b.set(col, nil)
	}
}

// ─── إيقاف / تفعيل — pause and resume ───────────────────────────────────

// pausableStatuses — the states an owner may switch off. These are exactly the
// browsable set: pausing means "stop showing me", so there is nothing to pause
// about a profile that is not being shown. A 'rejected', 'matched' or 'closed'
// profile is a staff decision and stays one.
const pausableStatuses = `('active','under_review','submitted')`

// PauseOwnProfile takes the profile out of the browse feed and remembers what
// to put it back to.
//
// The remembering happens in the same statement as the flip, so the two can
// never disagree. ErrNotOwner and ErrNotPausable are told apart by a second
// ownership-only probe AFTER the write has already failed — that probe reveals
// nothing a caller who owns the row does not already know, and it lets the app
// explain "your profile is still under review" instead of "not yours".
func (s *Store) PauseOwnProfile(ctx context.Context, profileID, ownerUserID int64) error {
	return s.setOwnPause(ctx, profileID, ownerUserID,
		`UPDATE marriage_profiles
		    SET paused_from_status = status,
		        status             = 'paused',
		        updated_at         = CURRENT_TIMESTAMP
		  WHERE id = $1 AND user_id = $2
		    AND owner_deleted_at IS NULL
		    AND status IN `+pausableStatuses)
}

// ResumeOwnProfile puts the profile back into the status it was paused from.
//
// COALESCE, not a literal 'active': a profile paused while awaiting review must
// come back awaiting review. If it always resumed to 'active', pause-then-resume
// would be a one-tap route from "submitted" to "approved by nobody". A NULL
// remembered status (a profile staff paused before migration 110) resumes to
// 'submitted' — back into the review queue, which is the safe direction to
// guess in.
func (s *Store) ResumeOwnProfile(ctx context.Context, profileID, ownerUserID int64) error {
	return s.setOwnPause(ctx, profileID, ownerUserID,
		`UPDATE marriage_profiles
		    SET status             = COALESCE(NULLIF(paused_from_status, ''), 'submitted'),
		        paused_from_status = NULL,
		        updated_at         = CURRENT_TIMESTAMP
		  WHERE id = $1 AND user_id = $2
		    AND owner_deleted_at IS NULL
		    AND status = 'paused'`)
}

// setOwnPause runs one of the two transitions above and maps "changed nothing"
// onto the right error. `sql` is a literal from this file.
func (s *Store) setOwnPause(ctx context.Context, profileID, ownerUserID int64, sql string) error {
	if profileID <= 0 || ownerUserID <= 0 {
		return errors.New("profileID and ownerUserID are required")
	}
	tag, err := s.Pool.Exec(ctx, sql, profileID, ownerUserID)
	if err != nil {
		return fmt.Errorf("change engagement profile %d pause state: %w", profileID, err)
	}
	if tag.RowsAffected() > 0 {
		return nil
	}
	// Nothing changed. Either it is not theirs (or not there), or it is theirs
	// and in the wrong state. Only the owner learns the difference.
	var owned bool
	if err := s.Pool.QueryRow(ctx,
		`SELECT COUNT(*) > 0 FROM marriage_profiles
		  WHERE id = $1 AND user_id = $2 AND owner_deleted_at IS NULL`,
		profileID, ownerUserID).Scan(&owned); err != nil {
		return fmt.Errorf("check ownership of engagement profile %d: %w", profileID, err)
	}
	if owned {
		return ErrNotPausable
	}
	return ErrNotOwner
}

// ─── حذف — the recoverable delete ───────────────────────────────────────

// DeleteOwnProfile removes the profile from every surface of the app while
// keeping every row it is attached to.
//
// WHY THIS IS NOT handlers.trashRow, WHICH IS THIS REPO'S RECOVERABLE DELETE.
// trashRow snapshots the row into trash_items and then DELETEs it, and its own
// comment records the limit: "FK cascades still fire for child rows; those
// children are not individually trashed". marriage_profiles has two ON DELETE
// CASCADE children —
//
//	marriage_chat_threads           (058) -> _messages, _reads
//	marriage_subscription_purchases (068)
//
// — so a trashRow delete here would destroy the user's mediated chat history
// and the record that they PAID for a subscription, and restoring from
// المهملات would bring back the profile row alone. That is silent data loss
// with a Trash entry on top of it, and a payment record is not something to
// lose because somebody tapped حذف.
//
// So the row stays: status moves to 'closed' (in the table's CHECK since
// migration 001, and already excluded from the browse feed) and
// owner_deleted_at is stamped, which is what List filters on and what tells
// staff a self-deletion apart from a closure they made. Staff restore it by
// making any status decision — AdminStatusHandler.Marriage clears the stamp.
//
// Deleting an already-deleted profile returns ErrNotOwner, the same answer a
// stranger gets, so the endpoint still leaks nothing.
func (s *Store) DeleteOwnProfile(ctx context.Context, profileID, ownerUserID int64) error {
	if profileID <= 0 || ownerUserID <= 0 {
		return errors.New("profileID and ownerUserID are required")
	}
	tag, err := s.Pool.Exec(ctx,
		`UPDATE marriage_profiles
		    SET owner_deleted_at = CURRENT_TIMESTAMP,
		        status           = 'closed',
		        updated_at       = CURRENT_TIMESTAMP
		  WHERE id = $1 AND user_id = $2 AND owner_deleted_at IS NULL`,
		profileID, ownerUserID)
	if err != nil {
		return fmt.Errorf("delete engagement profile %d: %w", profileID, err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotOwner
	}
	return nil
}
