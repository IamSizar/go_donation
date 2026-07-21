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
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
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
			return moduleDefaultAllowed(tier, module, action), nil
		}
		return false, err
	}
	return override, nil
}

// moduleDefaultAllowed applies per-module exceptions to the module-agnostic
// baseline. Today the only exception is `sensitive_data` (viewing contact info
// like phone/email): it defaults to admins only, so a Supervisor or Employee
// must be explicitly granted it in the matrix — the opposite of the normal
// "view is allowed by default" rule.
func moduleDefaultAllowed(tier Tier, module, action string) bool {
	if module == "sensitive_data" {
		return tier == TierSuperAdmin || tier == TierAdmin
	}
	return defaultAllowed(tier, action)
}

// Modules is the canonical list of dashboard resource slugs the Super Admin can
// tune permissions for. Keep in sync with the SPA nav.
var Modules = []string{
	"dashboard", "registrations", "users", "campaigns", "donations",
	"sponsorships", "beneficiary", "marketplace", "in_kind", "partners",
	"media", "community", "city", "marriage", "missions", "volunteers",
	"messages", "notifications", "push", "reports", "audit", "support", "trash",
	// §24 — cross-cutting "may view sensitive contact info (phone/email)" gate.
	// Only the `view` action is meaningful here; defaults to admins only.
	"sensitive_data",
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

// ── Note 31 — per-employee overrides ────────────────────────────────────
//
// Everything above resolves permissions per TIER: two employees on the same
// tier are always identical. AllowedForUser adds one more layer in front of
// that: a per-user override (module, action) → allowed, keyed by user_id
// alone (never tier), wins over the tier's own override/default. Clearing a
// user's override falls straight back to Allowed()'s tier-based answer — no
// separate "unset" state to track beyond "the row doesn't exist".

// AllowedForUser resolves the effective permission for a SPECIFIC staff
// member: their own override (if any) → their tier's override/default.
func (s *Store) AllowedForUser(ctx context.Context, userID int64, tier Tier, module, action string) (bool, error) {
	if tier == TierSuperAdmin {
		return true, nil
	}
	var override bool
	err := s.Pool.QueryRow(ctx,
		`SELECT allowed FROM role_permissions WHERE user_id=$1 AND module=$2 AND action=$3`,
		userID, module, action,
	).Scan(&override)
	if err == nil {
		return override, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return false, err
	}
	return s.Allowed(ctx, tier, module, action)
}

// UserOverride is one stored per-employee (module, action) → allowed row.
type UserOverride struct {
	Module  string `json:"module"`
	Action  string `json:"action"`
	Allowed bool   `json:"allowed"`
}

// ListUserOverrides returns every override stored for one specific user.
func (s *Store) ListUserOverrides(ctx context.Context, userID int64) ([]UserOverride, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT module, action, allowed FROM role_permissions WHERE user_id=$1 ORDER BY module, action`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []UserOverride{}
	for rows.Next() {
		var o UserOverride
		if err := rows.Scan(&o.Module, &o.Action, &o.Allowed); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// SetUserOverride upserts one per-employee (module, action) → allowed row.
// tier is stored alongside for the audit trail only; resolution never reads
// it back (AllowedForUser looks up by user_id alone).
func (s *Store) SetUserOverride(ctx context.Context, userID int64, tier Tier, module, action string, allowed bool) error {
	if tier == TierSuperAdmin {
		return errors.New("super_admin permissions cannot be overridden")
	}
	_, err := s.Pool.Exec(ctx,
		`INSERT INTO role_permissions (user_id, tier, module, action, allowed, updated_at)
		 VALUES ($1, $2, $3, $4, $5, NOW())
		 ON CONFLICT (user_id, module, action) WHERE user_id IS NOT NULL
		 DO UPDATE SET allowed = EXCLUDED.allowed, tier = EXCLUDED.tier, updated_at = NOW()`,
		userID, string(tier), module, action, allowed,
	)
	return err
}

// ClearUserOverride removes one per-employee override so the user falls back
// to their tier's own override/default again.
func (s *Store) ClearUserOverride(ctx context.Context, userID int64, module, action string) error {
	_, err := s.Pool.Exec(ctx,
		`DELETE FROM role_permissions WHERE user_id=$1 AND module=$2 AND action=$3`,
		userID, module, action,
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

// ── Requirement 6c — tamper-evident hash chain ─────────────────────────
//
// The ledger was already append-only (the app never UPDATEs/DELETEs rows). The
// chain makes it tamper-EVIDENT: each row stores prev_hash (the previous row's
// row_hash) and row_hash = sha256(prev_hash ∥ canonical(row)). Editing or
// deleting any row changes/invalidates every subsequent row_hash, which
// VerifyChain() detects. created_at is intentionally NOT part of the hash to
// avoid timestamp-precision round-trip fragility; the meaningful content
// (who / what / old → new / from-where) is fully covered.
const auditGenesisHash = "0000000000000000000000000000000000000000000000000000000000000000"

// auditChainLockKey is a fixed advisory-lock key that serializes chain appends
// so two concurrent writers can't read the same head and fork the chain.
const auditChainLockKey int64 = 6120240613

// auditRowHash computes a row's hash from the previous hash and the row's
// content. Fields are joined with the ASCII Unit Separator (0x1F), which cannot
// occur in these values, so the concatenation is unambiguous. Nil actor and
// empty/NULL text fields both canonicalize to "" — matching how VerifyChain
// reads them back.
func auditRowHash(prevHash string, actorID *int64, action, target, oldVal, newVal, ip string) string {
	actor := ""
	if actorID != nil {
		actor = strconv.FormatInt(*actorID, 10)
	}
	canonical := strings.Join([]string{prevHash, actor, action, target, oldVal, newVal, ip}, "\x1f")
	sum := sha256.Sum256([]byte(canonical))
	return hex.EncodeToString(sum[:])
}

// deref returns "" for a nil *string, else its value.
func deref(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// LogAudit appends an immutable, hash-chained record of a permission-related
// action. Failures are returned so callers can decide, but the audit row is
// best-effort by convention (a failed write must never block the security
// action itself). The whole append runs under an advisory lock + transaction so
// the prev→row hash linkage is race-free.
func (s *Store) LogAudit(ctx context.Context, actorID *int64, action, target, oldVal, newVal, ip string) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Serialize concurrent appenders so the chain head is read-modify-write safe.
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, auditChainLockKey); err != nil {
		return err
	}

	prev := auditGenesisHash
	var lastHash *string
	err = tx.QueryRow(ctx,
		`SELECT row_hash FROM permission_audit_log ORDER BY id DESC LIMIT 1`).Scan(&lastHash)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if lastHash != nil && *lastHash != "" {
		prev = *lastHash
	}

	rowHash := auditRowHash(prev, actorID, action, target, oldVal, newVal, ip)
	if _, err := tx.Exec(ctx,
		`INSERT INTO permission_audit_log
		   (actor_id, action, target, old_value, new_value, ip_address, prev_hash, row_hash)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		actorID, action, nullIfEmpty(target), nullIfEmpty(oldVal), nullIfEmpty(newVal), nullIfEmpty(ip),
		prev, rowHash,
	); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// BackfillChain stamps prev_hash/row_hash onto any rows that predate the chain
// (e.g. rows written before migration 024, or on an environment where the
// column was just added). Idempotent: rows that already have a row_hash are
// left untouched, and it chains the remaining NULL rows in id order onto the
// existing head. Safe to call once at startup.
func (s *Store) BackfillChain(ctx context.Context) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, auditChainLockKey); err != nil {
		return err
	}

	// Head = row_hash of the highest already-hashed row (genesis if none).
	prev := auditGenesisHash
	var head *string
	err = tx.QueryRow(ctx,
		`SELECT row_hash FROM permission_audit_log
		  WHERE row_hash IS NOT NULL ORDER BY id DESC LIMIT 1`).Scan(&head)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if head != nil && *head != "" {
		prev = *head
	}

	rows, err := tx.Query(ctx,
		`SELECT id, actor_id, action, target, old_value, new_value, ip_address
		   FROM permission_audit_log
		  WHERE row_hash IS NULL ORDER BY id`)
	if err != nil {
		return err
	}
	type pending struct {
		id                            int64
		actorID                       *int64
		action                        string
		target, oldVal, newVal, ipAdr *string
	}
	var todo []pending
	for rows.Next() {
		var p pending
		if err := rows.Scan(&p.id, &p.actorID, &p.action, &p.target, &p.oldVal, &p.newVal, &p.ipAdr); err != nil {
			rows.Close()
			return err
		}
		todo = append(todo, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, p := range todo {
		rowHash := auditRowHash(prev, p.actorID, p.action, deref(p.target), deref(p.oldVal), deref(p.newVal), deref(p.ipAdr))
		if _, err := tx.Exec(ctx,
			`UPDATE permission_audit_log SET prev_hash = $2, row_hash = $3 WHERE id = $1`,
			p.id, prev, rowHash); err != nil {
			return err
		}
		prev = rowHash
	}
	return tx.Commit(ctx)
}

// ChainStatus is the result of verifying the audit ledger's hash chain.
type ChainStatus struct {
	Intact   bool   `json:"intact"`
	Count    int    `json:"count"`
	BrokenAt *int64 `json:"broken_at_id"` // id of the first row that fails to verify
}

// VerifyChain walks the ledger in id order and recomputes each row_hash from the
// running previous hash. It returns intact=false with the offending row id on
// the first mismatch (a content edit, a deletion, or a reordering all surface
// here). An empty ledger is trivially intact.
func (s *Store) VerifyChain(ctx context.Context) (ChainStatus, error) {
	rows, err := s.Pool.Query(ctx,
		`SELECT id, actor_id, action, target, old_value, new_value, ip_address, prev_hash, row_hash
		   FROM permission_audit_log ORDER BY id`)
	if err != nil {
		return ChainStatus{}, err
	}
	defer rows.Close()

	prev := auditGenesisHash
	count := 0
	for rows.Next() {
		var (
			id                            int64
			actorID                       *int64
			action                        string
			target, oldVal, newVal, ipAdr *string
			prevHash, rowHash             *string
		)
		if err := rows.Scan(&id, &actorID, &action, &target, &oldVal, &newVal, &ipAdr, &prevHash, &rowHash); err != nil {
			return ChainStatus{}, err
		}
		count++
		want := auditRowHash(prev, actorID, action, deref(target), deref(oldVal), deref(newVal), deref(ipAdr))
		if rowHash == nil || *rowHash != want || deref(prevHash) != prev {
			bad := id
			return ChainStatus{Intact: false, Count: count, BrokenAt: &bad}, rows.Err()
		}
		prev = *rowHash
	}
	if err := rows.Err(); err != nil {
		return ChainStatus{}, err
	}
	return ChainStatus{Intact: true, Count: count}, nil
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
