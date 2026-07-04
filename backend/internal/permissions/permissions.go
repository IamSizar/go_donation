// Package permissions implements the Phase 6 dashboard access model: a small
// set of staff tiers with per-module/per-action permissions.
//
// Design: each tier has a built-in DEFAULT for every action; the
// role_permissions table stores only OVERRIDES (a Super Admin toggling a
// specific tier+module+action). The effective answer is:
//
//	Allowed = override(tier, module, action)   if a row exists
//	        = default(tier, action)            otherwise
//
// super_admin is always allowed and is never stored as overridable.
package permissions

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Tier is a dashboard staff access tier, highest to lowest privilege.
type Tier string

const (
	TierSuperAdmin Tier = "super_admin"
	TierAdmin      Tier = "admin"
	TierSupervisor Tier = "supervisor"
	TierEmployee   Tier = "employee"
	TierUser       Tier = "user"
)

// Actions a tier can perform on a module.
const (
	ActionView    = "view"
	ActionAdd     = "add"
	ActionEdit    = "edit"
	ActionArchive = "archive"
	ActionDelete  = "delete"
	ActionExport  = "export"
)

// TierFrom normalizes a raw string (or empty) to a known tier, defaulting to
// the least-privileged 'user'.
func TierFrom(s string) Tier {
	switch Tier(s) {
	case TierSuperAdmin, TierAdmin, TierSupervisor, TierEmployee:
		return Tier(s)
	default:
		return TierUser
	}
}

// CanAccessDashboard is the A-19 gate: only staff tiers may reach the admin
// dashboard at all. Plain app users (donors/beneficiaries/volunteers) can't.
func CanAccessDashboard(tier Tier) bool {
	return tier == TierSuperAdmin || tier == TierAdmin ||
		tier == TierSupervisor || tier == TierEmployee
}

// defaultAllowed is the built-in baseline for a tier+action, before any
// role_permissions override. Kept module-agnostic; the override table adds the
// per-module nuance a Super Admin configures.
func defaultAllowed(tier Tier, action string) bool {
	switch tier {
	case TierSuperAdmin, TierAdmin:
		// Admins do everything by default. (Permissions-management itself is
		// guarded separately and restricted to super_admin.)
		return true
	case TierSupervisor:
		switch action {
		case ActionView, ActionAdd, ActionEdit, ActionArchive, ActionExport:
			return true
		default: // delete
			return false
		}
	case TierEmployee:
		switch action {
		case ActionView, ActionEdit:
			return true
		default:
			return false
		}
	default: // user
		return false
	}
}

// Store answers permission questions against the role_permissions override
// table.
type Store struct{ Pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{Pool: pool} }

// Allowed reports whether a tier may perform action on module, honoring any
// stored override and falling back to the tier default.
func (s *Store) Allowed(ctx context.Context, tier Tier, module, action string) (bool, error) {
	if tier == TierSuperAdmin {
		return true, nil
	}
	var override bool
	err := s.Pool.QueryRow(ctx,
		`SELECT allowed FROM role_permissions WHERE tier=$1 AND module=$2 AND action=$3`,
		string(tier), module, action,
	).Scan(&override)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return defaultAllowed(tier, action), nil
		}
		return false, err
	}
	return override, nil
}

// Modules is the canonical list of dashboard resource slugs the Super Admin can
// tune permissions for. Keep in sync with the SPA nav.
var Modules = []string{
	"dashboard", "registrations", "users", "campaigns", "donations",
	"sponsorships", "beneficiary", "marketplace", "in_kind", "partners",
	"media", "community", "city", "marriage", "missions", "volunteers",
	"messages", "notifications", "push", "reports", "audit", "support", "trash",
}

// AllActions is the ordered list of actions the matrix exposes per module.
var AllActions = []string{ActionView, ActionAdd, ActionEdit, ActionArchive, ActionDelete, ActionExport}

// AllTiers is the set of non-super tiers a Super Admin can configure (super_admin
// is omitted — it is always fully allowed and never overridable).
var AllTiers = []string{string(TierAdmin), string(TierSupervisor), string(TierEmployee), string(TierUser)}

// Override is one stored (tier, module, action) permission override.
type Override struct {
	Tier    string `json:"tier"`
	Module  string `json:"module"`
	Action  string `json:"action"`
	Allowed bool   `json:"allowed"`
}

// DefaultAllowed exposes the built-in baseline for a tier+action so callers
// (e.g. the matrix API) can show which cells differ from the default.
func DefaultAllowed(tier Tier, action string) bool { return defaultAllowed(tier, action) }

// ListOverrides returns every stored override row.
func (s *Store) ListOverrides(ctx context.Context) ([]Override, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT tier, module, action, allowed FROM role_permissions ORDER BY tier, module, action`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Override{}
	for rows.Next() {
		var o Override
		if err := rows.Scan(&o.Tier, &o.Module, &o.Action, &o.Allowed); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// SetOverride upserts a single (tier, module, action) → allowed override.
// super_admin is never stored (it is always allowed).
func (s *Store) SetOverride(ctx context.Context, tier, module, action string, allowed bool) error {
	if TierFrom(tier) == TierSuperAdmin {
		return errors.New("super_admin permissions cannot be overridden")
	}
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO role_permissions (tier, module, action, allowed, updated_at)
		 VALUES ($1, $2, $3, $4, NOW())
		 ON CONFLICT (tier, module, action)
		 DO UPDATE SET allowed = EXCLUDED.allowed, updated_at = NOW()`,
		tier, module, action, allowed,
	)
	return err
}

// AuditEntry is one row of the immutable permission_audit_log.
type AuditEntry struct {
	ID        int64     `json:"id"`
	ActorID   *int64    `json:"actor_id"`
	ActorName *string   `json:"actor_name"`
	Action    string    `json:"action"`
	Target    *string   `json:"target"`
	OldValue  *string   `json:"old_value"`
	NewValue  *string   `json:"new_value"`
	IPAddress *string   `json:"ip_address"`
	CreatedAt time.Time `json:"created_at"`
}

// LogAudit appends an immutable record of a permission-related action. Failures
// are returned so callers can decide, but the audit row is best-effort by
// convention (a failed write must never block the security action itself).
func (s *Store) LogAudit(ctx context.Context, actorID *int64, action, target, oldVal, newVal, ip string) error {
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO permission_audit_log (actor_id, action, target, old_value, new_value, ip_address)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		actorID, action, nullIfEmpty(target), nullIfEmpty(oldVal), nullIfEmpty(newVal), nullIfEmpty(ip),
	)
	return err
}

// ListAudit returns the most recent audit rows (newest first), resolving the
// actor's display name where possible.
func (s *Store) ListAudit(ctx context.Context, limit int) ([]AuditEntry, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT l.id, l.actor_id, COALESCE(p.full_name, u.username),
		        l.action, l.target, l.old_value, l.new_value, l.ip_address, l.created_at
		   FROM permission_audit_log l
		   LEFT JOIN users u ON u.id = l.actor_id
		   LEFT JOIN user_profiles p ON p.user_id = l.actor_id
		  ORDER BY l.created_at DESC
		  LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []AuditEntry{}
	for rows.Next() {
		var e AuditEntry
		if err := rows.Scan(&e.ID, &e.ActorID, &e.ActorName, &e.Action, &e.Target,
			&e.OldValue, &e.NewValue, &e.IPAddress, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
