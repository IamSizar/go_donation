// Package staffactivity answers one question about one staff member: what has
// this person actually done?
//
// WHY IT EXISTS
// The owner asked for "an employee profile created by the super admin,
// containing all of his actions and activity and all the causes he handled and
// accepted". The dashboard could already list staff (who they are) and show a
// global audit log (what happened, to everything, by everyone). Neither
// answers the question a manager actually asks, which is about ONE person:
// nothing joined the two together.
//
// WHERE THE DATA COMES FROM, AND WHY NOTHING NEW IS LOGGED
// Every decision a staff member makes is already stamped with their id, in the
// table the decision belongs to:
//
//	beneficiary_cases.reviewed_by_user_id      the cases they reviewed
//	users.registration_reviewed_by             the registrations they decided
//	profile_change_requests.decided_by         name/photo changes they decided
//	marriage_meeting_requests.decided_by       meeting requests they decided
//	permission_audit_log.actor_id              permission and tier changes
//
// So this package reads what is there rather than adding a second, parallel
// log that could disagree with it. A new audit table would have to be written
// at every one of those call sites and would be wrong the first time somebody
// forgot one; these columns cannot be forgotten, because the decision cannot be
// recorded without them.
//
// WHAT IS DELIBERATELY NOT ON THE TIMELINE
// Chat assignments (chat_threads.assigned_staff_user_id and the case/volunteer
// equivalent) carry no timestamp for WHEN the claim happened — the column is
// current state, not an event. Putting them on a dated timeline would mean
// showing the thread's last-message time as though it were the moment of
// claiming, which is a plausible-looking lie. They are reported as counts of
// what the person holds RIGHT NOW, under their own heading, and the API says
// so in the field name.
package staffactivity

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store reads staff activity. Same shape as the other stores in internal/.
type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Entry is one dated thing a staff member did.
type Entry struct {
	// Which stream it came from: "case", "registration", "profile_change",
	// "meeting_request", "permission". The dashboard groups and filters on
	// this, so it is a stable key, not a label.
	Kind string `json:"kind"`
	// The decision itself, as the source table records it — "approved",
	// "rejected", "verified", or for permissions the action name. Passed
	// through unchanged: inventing a vocabulary here would put words in the
	// data's mouth.
	Action string `json:"action"`
	// What it was done to, in a human's terms: a case code, a person's name,
	// a permission target. May be empty when the record has nothing readable.
	Subject string `json:"subject"`
	// The affected record's id, so the dashboard can link to it.
	EntityID int64 `json:"entity_id"`
	// When the decision was recorded.
	At time.Time `json:"at"`
}

// Summary is the whole profile: who they are, how much they have done, what
// they are holding now, and the most recent of it in order.
type Summary struct {
	UserID    int64      `json:"user_id"`
	Name      string     `json:"name"`
	Phone     string     `json:"phone"`
	StaffTier string     `json:"staff_tier"`
	Active    bool       `json:"active"`
	JoinedAt  *time.Time `json:"joined_at"`

	Totals    Totals  `json:"totals"`
	OpenWork  Holding `json:"currently_assigned"`
	Timeline  []Entry `json:"timeline"`
	Truncated bool    `json:"timeline_truncated"`
}

// Totals counts every decision on record, not merely the ones in the timeline
// window — a person with 900 decisions must not read as having 50.
type Totals struct {
	Cases             int `json:"cases_reviewed"`
	Registrations     int `json:"registrations_reviewed"`
	ProfileChanges    int `json:"profile_changes_decided"`
	MeetingRequests   int `json:"meeting_requests_decided"`
	PermissionChanges int `json:"permission_changes"`
	All               int `json:"all"`
}

// Holding is current state, not history — see the package note.
type Holding struct {
	DonorChats         int `json:"donor_chats"`
	CaseVolunteerChats int `json:"case_volunteer_chats"`
}

// timelineSQL unions the five dated sources.
//
// One query rather than five round trips, because the answer is a single
// ordered list: sorting and limiting five separate result sets in Go would
// mean fetching far more rows than are shown, and getting the "most recent 50
// across all kinds" wrong the moment one stream is busier than the others.
//
// Every branch requires its timestamp to be NOT NULL. A decision column set
// with no decided_at is a half-written row, and dating it "now" or leaving it
// at the zero time would both put a falsehood on the timeline.
const timelineSQL = `
	SELECT kind, action, subject, entity_id, at FROM (
		SELECT 'case'::text AS kind,
		       COALESCE(NULLIF(c.verification_status, ''), 'reviewed') AS action,
		       COALESCE(NULLIF(c.case_code, ''), c.full_name, '') AS subject,
		       c.id AS entity_id,
		       c.reviewed_at AS at
		  FROM beneficiary_cases c
		 WHERE c.reviewed_by_user_id = $1 AND c.reviewed_at IS NOT NULL

		UNION ALL
		SELECT 'registration', u.registration_status,
		       COALESCE(NULLIF(p.full_name, ''), u.username, ''),
		       u.id, u.registration_reviewed_at
		  FROM users u
		  LEFT JOIN user_profiles p ON p.user_id = u.id
		 WHERE u.registration_reviewed_by = $1 AND u.registration_reviewed_at IS NOT NULL

		UNION ALL
		SELECT 'profile_change', r.status, r.field, r.id, r.decided_at
		  FROM profile_change_requests r
		 WHERE r.decided_by = $1 AND r.decided_at IS NOT NULL

		UNION ALL
		SELECT 'meeting_request', m.status, m.request_type, m.id, m.decided_at
		  FROM marriage_meeting_requests m
		 WHERE m.decided_by = $1 AND m.decided_at IS NOT NULL

		UNION ALL
		SELECT 'permission', a.action, COALESCE(a.target, ''), a.id, a.created_at
		  FROM permission_audit_log a
		 WHERE a.actor_id = $1
	) t
	ORDER BY at DESC
	LIMIT $2`

// Load builds the profile for one staff member.
//
// limit caps the timeline only; the totals are counted across everything, so
// the two never disagree about how much this person has done.
func (s *Store) Load(ctx context.Context, userID int64, limit int) (*Summary, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}

	var out Summary
	out.UserID = userID
	err := s.Pool.QueryRow(ctx, `
		SELECT COALESCE(NULLIF(p.full_name, ''), u.username, ''),
		       COALESCE(u.phone, ''),
		       COALESCE(u.staff_tier, 'user'),
		       COALESCE(u.active, 0) = 1,
		       u.created_at
		  FROM users u
		  LEFT JOIN user_profiles p ON p.user_id = u.id
		 WHERE u.id = $1`, userID,
	).Scan(&out.Name, &out.Phone, &out.StaffTier, &out.Active, &out.JoinedAt)
	if err != nil {
		return nil, err
	}

	// Counts come from the same predicates as the timeline branches. They are
	// written out rather than derived from the union so a limit can never
	// silently become the total.
	err = s.Pool.QueryRow(ctx, `
		SELECT
		  (SELECT COUNT(*) FROM beneficiary_cases
		    WHERE reviewed_by_user_id = $1 AND reviewed_at IS NOT NULL),
		  (SELECT COUNT(*) FROM users
		    WHERE registration_reviewed_by = $1 AND registration_reviewed_at IS NOT NULL),
		  (SELECT COUNT(*) FROM profile_change_requests
		    WHERE decided_by = $1 AND decided_at IS NOT NULL),
		  (SELECT COUNT(*) FROM marriage_meeting_requests
		    WHERE decided_by = $1 AND decided_at IS NOT NULL),
		  (SELECT COUNT(*) FROM permission_audit_log WHERE actor_id = $1),
		  (SELECT COUNT(*) FROM chat_threads WHERE assigned_staff_user_id = $1),
		  (SELECT COUNT(*) FROM case_volunteer_chat_threads WHERE assigned_staff_user_id = $1)`,
		userID,
	).Scan(
		&out.Totals.Cases, &out.Totals.Registrations, &out.Totals.ProfileChanges,
		&out.Totals.MeetingRequests, &out.Totals.PermissionChanges,
		&out.OpenWork.DonorChats, &out.OpenWork.CaseVolunteerChats,
	)
	if err != nil {
		return nil, err
	}
	out.Totals.All = out.Totals.Cases + out.Totals.Registrations +
		out.Totals.ProfileChanges + out.Totals.MeetingRequests +
		out.Totals.PermissionChanges

	rows, err := s.Pool.Query(ctx, timelineSQL, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out.Timeline = []Entry{}
	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.Kind, &e.Action, &e.Subject, &e.EntityID, &e.At); err != nil {
			return nil, err
		}
		out.Timeline = append(out.Timeline, e)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Says plainly that there is more, so the page never implies the list is
	// the whole history.
	out.Truncated = out.Totals.All > len(out.Timeline)
	return &out, nil
}
