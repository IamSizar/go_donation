package users

import (
	"context"
	"encoding/json"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
)

// ProfileRow is the raw user_profiles row used for diffs / responses.
type ProfileRow struct {
	ProfileID      int64
	UserID         int64
	FullName       string
	Gender         string
	Address        string
	ProfilePicture string
	DateOfBirth    string // "YYYY-MM-DD" or "" when null
}

// UpdateRoleID sets users.role_id. Matches updateUserRoleById() in PHP.
func (s *Store) UpdateRoleID(ctx context.Context, userID int64, roleID int) error {
	if userID <= 0 || roleID <= 0 {
		return errors.New("invalid userID or roleID")
	}
	_, err := s.Pool.Exec(ctx,
		`UPDATE users SET role_id = $1 WHERE id = $2`, roleID, userID,
	)
	return err
}

// UserExists returns true if a row exists in users with the given id.
func (s *Store) UserExists(ctx context.Context, userID int64) (bool, error) {
	if userID <= 0 {
		return false, nil
	}
	var x int
	err := s.Pool.QueryRow(ctx, `SELECT 1 FROM users WHERE id = $1`, userID).Scan(&x)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// GetProfileRow returns the current user_profiles row, or nil if none exists.
func (s *Store) GetProfileRow(ctx context.Context, userID int64) (*ProfileRow, error) {
	var r ProfileRow
	err := s.Pool.QueryRow(ctx,
		`SELECT id, user_id, full_name, address, gender, profile_picture,
		        COALESCE(to_char(date_of_birth, 'YYYY-MM-DD'), '')
		   FROM user_profiles WHERE user_id = $1 LIMIT 1`,
		userID,
	).Scan(&r.ProfileID, &r.UserID, &r.FullName, &r.Address, &r.Gender, &r.ProfilePicture, &r.DateOfBirth)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &r, nil
}

// ProfileUpdate carries the optional fields supplied by the /profile/set endpoint.
// Any pointer left nil is interpreted as "don't change this column".
type ProfileUpdate struct {
	FullName       *string
	Address        *string
	Gender         *string
	DateOfBirth    *string // non-nil => set; "" clears to NULL. Expects "YYYY-MM-DD".
	PicturePathSet *string // non-nil => set to this value
	RemovePicture  bool    // true => set picture to NULL (overrides PicturePathSet)
}

// UpsertProfile ports upsertUserProfileWithDefaults(). Returns the resulting row.
// Writes audit-log entries for each field that changed.
func (s *Store) UpsertProfile(
	ctx context.Context,
	userID int64,
	upd ProfileUpdate,
	actorSource string,
	actorUserID int64,
	auditMetadata map[string]any,
) (*ProfileRow, error) {
	if userID <= 0 {
		return nil, errors.New("invalid userID")
	}
	exists, err := s.UserExists(ctx, userID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, errors.New("user not found")
	}

	current, err := s.GetProfileRow(ctx, userID)
	if err != nil {
		return nil, err
	}

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if current == nil {
		// INSERT — user_profiles columns are NOT NULL in the schema. Use the same
		// "1" literal default the PHP code falls back to so an unsupplied field
		// doesn't collide with NOT NULL.
		full := "1"
		if upd.FullName != nil {
			full = *upd.FullName
		}
		addr := "1"
		if upd.Address != nil {
			addr = *upd.Address
		}
		gender := ""
		if upd.Gender != nil {
			gender = *upd.Gender
		}
		picture := "0" // matches schema DEFAULT '0'
		if upd.PicturePathSet != nil && !upd.RemovePicture {
			picture = *upd.PicturePathSet
		}
		// date_of_birth is nullable — pass nil (=> NULL) unless a non-empty
		// "YYYY-MM-DD" was supplied.
		var dobArg any = nil
		if upd.DateOfBirth != nil && strings.TrimSpace(*upd.DateOfBirth) != "" {
			dobArg = strings.TrimSpace(*upd.DateOfBirth)
		}

		_, err = tx.Exec(ctx,
			`INSERT INTO user_profiles (user_id, full_name, address, gender, profile_picture, date_of_birth)
			 VALUES ($1, $2, $3, $4, $5, $6)`,
			userID, full, addr, gender, picture, dobArg,
		)
		if err != nil {
			return nil, err
		}
	} else {
		// UPDATE — only set columns that were explicitly provided.
		sets := []string{}
		args := []any{}
		i := 1
		if upd.FullName != nil {
			sets = append(sets, "full_name = $"+itoa(i))
			args = append(args, *upd.FullName)
			i++
		}
		if upd.Address != nil {
			sets = append(sets, "address = $"+itoa(i))
			args = append(args, *upd.Address)
			i++
		}
		if upd.Gender != nil {
			sets = append(sets, "gender = $"+itoa(i))
			args = append(args, *upd.Gender)
			i++
		}
		if upd.DateOfBirth != nil {
			if strings.TrimSpace(*upd.DateOfBirth) == "" {
				sets = append(sets, "date_of_birth = NULL")
			} else {
				sets = append(sets, "date_of_birth = $"+itoa(i))
				args = append(args, strings.TrimSpace(*upd.DateOfBirth))
				i++
			}
		}
		if upd.RemovePicture {
			sets = append(sets, "profile_picture = '0'")
		} else if upd.PicturePathSet != nil {
			sets = append(sets, "profile_picture = $"+itoa(i))
			args = append(args, *upd.PicturePathSet)
			i++
		}

		if len(sets) > 0 {
			args = append(args, userID)
			_, err = tx.Exec(ctx,
				`UPDATE user_profiles SET `+strings.Join(sets, ", ")+
					` WHERE user_id = $`+itoa(i),
				args...,
			)
			if err != nil {
				return nil, err
			}
		}
	}

	// Fetch the post-update row inside the same transaction for the response/audit.
	var updated ProfileRow
	err = tx.QueryRow(ctx,
		`SELECT id, user_id, full_name, address, gender, profile_picture,
		        COALESCE(to_char(date_of_birth, 'YYYY-MM-DD'), '')
		   FROM user_profiles WHERE user_id = $1`,
		userID,
	).Scan(&updated.ProfileID, &updated.UserID, &updated.FullName, &updated.Address, &updated.Gender, &updated.ProfilePicture, &updated.DateOfBirth)
	if err != nil {
		return nil, err
	}

	// Write audit entries for any field that actually changed.
	if current != nil {
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"full_name", current.FullName, updated.FullName)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"address", current.Address, updated.Address)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"gender", current.Gender, updated.Gender)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"date_of_birth", current.DateOfBirth, updated.DateOfBirth)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"profile_picture", current.ProfilePicture, updated.ProfilePicture)
	} else {
		// Creating a new profile counts as setting each field from nothing.
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"full_name", "", updated.FullName)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"address", "", updated.Address)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"gender", "", updated.Gender)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"date_of_birth", "", updated.DateOfBirth)
		s.recordAudit(ctx, tx, userID, actorSource, actorUserID, auditMetadata,
			"profile_picture", "", updated.ProfilePicture)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &updated, nil
}

func (s *Store) recordAudit(
	ctx context.Context,
	tx pgx.Tx,
	userID int64,
	actorSource string,
	actorUserID int64,
	metadata map[string]any,
	field, oldVal, newVal string,
) {
	if oldVal == newVal {
		return
	}
	if actorSource == "" {
		actorSource = "user"
	}
	var actor any = nil
	if actorUserID > 0 {
		actor = actorUserID
	}
	var oldArg any = oldVal
	if oldVal == "" {
		oldArg = nil
	}
	var newArg any = newVal
	if newVal == "" {
		newArg = nil
	}
	var metaJSON any = nil
	if len(metadata) > 0 {
		if b, err := json.Marshal(metadata); err == nil {
			metaJSON = string(b)
		}
	}
	_, _ = tx.Exec(ctx,
		`INSERT INTO user_profile_audit_logs
		   (user_id, actor_source, actor_user_id, changed_field, old_value, new_value, metadata_json)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		userID, actorSource, actor, field, oldArg, newArg, metaJSON,
	)
}

// itoa avoids pulling strconv into every call site.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
