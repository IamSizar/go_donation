// Package chatgroups implements OPOS #25284's staff-created group chats.
//
// Two modes share one schema (see the migration for the full column list):
//   - kind='masked' — donor/beneficiary/volunteer groups. Non-staff members
//     see only a staff-assigned label, never a real name, phone, avatar, or
//     user id. Staff always sees real identities via the Admin* methods.
//   - kind='team' — volunteer team coordination. Real names, ordinary group
//     chat, staff curates membership.
//
// The masking guarantee is structural, not a filter someone could forget:
// GroupMessage (the type every non-staff response is built from) has no
// field capable of holding a user id or a real name. See
// docs/superpowers/specs/2026-09-12-masked-group-chats-design.md §5.
package chatgroups

import (
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	Pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Kind is a chat_group_threads.kind value.
type Kind string

const (
	KindMasked Kind = "masked"
	KindTeam   Kind = "team"
)

// Group mirrors one chat_group_threads row.
type Group struct {
	ID          int64
	Kind        Kind
	MemberTitle string
	CreatedBy   int64
	Lifecycle   string
	CreatedAt   string
}

// MemberInput is what a caller supplies when adding someone to a group.
// Label is optional — a masked group auto-generates one ("Donor 1") when
// left blank; a team group ignores it (team members are never masked).
type MemberInput struct {
	UserID      int64
	RoleInGroup string
	Label       string
}

// GroupMessage is what a non-staff member's response is built from. It has
// NO user-id field — it is not possible to leak a real identity through
// this type because the type cannot hold one.
type GroupMessage struct {
	ID             int64  `json:"id"`
	SenderMemberID int64  `json:"sender_member_id"`
	SenderLabel    string `json:"sender_label"`
	IsMine         bool   `json:"is_mine"`
	Body           string `json:"body"`
	CreatedAt      string `json:"created_at"`
}

// AdminGroupMessage is staff-only. Deliberately NOT built by embedding
// GroupMessage — a fully independent type, so nothing about the masked
// type's shape can be reused by mistake for a response that should carry
// real identity.
type AdminGroupMessage struct {
	ID             int64  `json:"id"`
	SenderMemberID int64  `json:"sender_member_id"`
	SenderUserID   int64  `json:"sender_user_id"`
	SenderName     string `json:"sender_name"`
	Body           string `json:"body"`
	CreatedAt      string `json:"created_at"`
}
