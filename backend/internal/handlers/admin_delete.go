package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/karam-flutter/humanitarian-backend/internal/auth"
	"github.com/karam-flutter/humanitarian-backend/internal/casevolchat"
	"github.com/karam-flutter/humanitarian-backend/internal/deleteguard"
)

// AdminDeleteHandler exposes the delete endpoints for Phase 13.
//
// Pattern: every handler moves the row to the Trash via trashRow and returns:
//   - 200 {success, id, trashed}            — row moved to the Trash
//   - 404 {success:false, error}            — id not found
//   - 409 {success:false, error}            — FK violation (row is referenced
//     by another table). Includes the
//     Postgres "detail" string so the
//     admin sees which child rows are
//     blocking, e.g.
//     "violates foreign key constraint
//     ... on table sponsorships."
//   - 500 {success:false, error}            — any other DB error
//
// All routes are wired under the `admin` group; RequireAdmin authenticates
// before any of these run.
type AdminDeleteHandler struct {
	Pool *pgxpool.Pool
}

func NewAdminDeleteHandler(pool *pgxpool.Pool) *AdminDeleteHandler {
	return &AdminDeleteHandler{Pool: pool}
}

// deleteRow is the AdminDeleteHandler entry point: parse the :id and trash it.
func (h *AdminDeleteHandler) deleteRow(c *gin.Context, table string) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	trashRow(c, h.Pool, table, id)
}

// trashRow moves a row to the Trash instead of hard-deleting it (Phase 7 ·
// G-06 / A-16): it snapshots the whole row as a JSON document into trash_items,
// then removes it from the source table — both in one transaction, so a row is
// never lost nor left half-deleted. A Super-Admin can later restore or purge it.
//
// H15 — this used to be a private method on AdminDeleteHandler, which is the
// whole reason 15 of the 31 admin delete routes hard-deleted instead: the
// catalogue, task and comment handlers live in other files with their own
// stores and simply could not reach it. It is a package-level function now, so
// "delete" means the same thing wherever it is written.
//
// It writes the HTTP response itself and reports whether the row was trashed,
// so a caller with a side effect to run afterwards (a cache to invalidate, a
// notification to send) can key off the result instead of guessing.
//
// `table` MUST be a literal from this package — it is interpolated into the SQL.
// Never pass anything derived from a request.
func trashRow(c *gin.Context, pool *pgxpool.Pool, table string, id int64) bool {
	ctx := c.Request.Context()

	// Who performed the delete (for the trash audit trail).
	var actor *int64
	if u, ok := auth.UserFromGin(c); ok && u != nil {
		actor = &u.UserID
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}
	defer tx.Rollback(ctx)

	// 1) Snapshot the full row as a JSON document (for a faithful restore).
	var payload []byte
	err = tx.QueryRow(ctx,
		"SELECT to_jsonb(t.*) FROM "+table+" t WHERE t.id = $1", id,
	).Scan(&payload)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": "Not found."})
			return false
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}

	// 2) Archive it into the central trash container.
	if _, err = tx.Exec(ctx,
		`INSERT INTO trash_items (source_table, row_id, payload, deleted_by)
		 VALUES ($1, $2, $3, $4)`, table, id, payload, actor,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}

	// 3) Remove from the source table. FK cascades still fire for child rows;
	//    those children are not individually trashed (restoring the parent
	//    brings back the parent row only).
	if _, err = tx.Exec(ctx, "DELETE FROM "+table+" WHERE id = $1", id); err != nil {
		// Translate FK violation (23503) into a friendly 409 so admins
		// understand why a row can't be deleted yet.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			msg := "Cannot delete: still referenced by another record."
			if pgErr.Detail != "" {
				msg = msg + " " + pgErr.Detail
			}
			c.JSON(http.StatusConflict, gin.H{"success": false, "error": msg})
			return false
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}

	if err = tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "Database error: " + err.Error()})
		return false
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "id": id, "trashed": true})
	return true
}

// ===== one handler per resource (mirrors admin_edit.go) =====

func (h *AdminDeleteHandler) Partner(c *gin.Context)   { h.deleteRow(c, "partners") }
func (h *AdminDeleteHandler) Media(c *gin.Context)     { h.deleteRow(c, "media_posts") }
func (h *AdminDeleteHandler) Community(c *gin.Context) { h.deleteRow(c, "city_directory_entries") }

// Marriage deletes an engagement profile from the staff dashboard.
//
// K14 WAS ONLY HALF-APPLIED, AND THIS IS THE OTHER HALF. Commit 9f6ec79
// deliberately kept the OWNER's own حذف out of trashRow —
// internal/marriage/owner.go stamps owner_deleted_at instead and explains why
// at length: marriage_profiles cascades to marriage_chat_threads (→ messages,
// reads) AND to marriage_subscription_purchases, the record that the user PAID.
// But that reasoning was applied only to the owner's route. The staff route
// still put the same table through trashRow, so the hazard K14 documents was
// live on the admin side, and a protection reported as shipped was half
// missing.
//
// WHY A REFUSAL HERE AND A STAMP THERE. K14 needed a stamp because the profile
// had to vanish from a PUBLIC browse feed and from the owner's own list while
// the row stayed; only a column can do that. Staff need nothing of the kind —
// POST /api/admin/marriage/:id/status already moves a profile to 'closed' or
// 'rejected', which takes it out of the working list — so a refusal costs the
// operator nothing they cannot get another way, and adds no column and no
// migration. The two halves now agree on the outcome (the messages and the
// payment survive) by the means each side actually needs.
//
// Messages, not threads, for the reason ee50aae gives: staff approving a
// meeting request opens the thread before anyone has typed.
func (h *AdminDeleteHandler) Marriage(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	records, err := deleteguard.New(h.Pool).ForMarriageProfile(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}
	if records.Any() {
		c.JSON(http.StatusConflict, gin.H{
			"success":                false,
			"code":                   "marriage_profile_has_records",
			"messages":               records.Messages,
			"subscription_purchases": records.SubscriptionPurchases,
			"error": "Cannot delete: this engagement profile has chat messages or a subscription " +
				"payment, and deleting it would permanently destroy them. Set its status to " +
				"closed or rejected instead.",
		})
		return
	}
	trashRow(c, h.Pool, "marriage_profiles", id)
}

func (h *AdminDeleteHandler) MarketplaceProduct(c *gin.Context) {
	h.deleteRow(c, "marketplace_products")
}
func (h *AdminDeleteHandler) MarketplaceOrder(c *gin.Context) { h.deleteRow(c, "marketplace_orders") }

// BeneficiaryCase deletes a case — the SECOND DOOR onto the conversation
// ee50aae protected on the signup route.
//
// case_volunteer_chat_threads hangs off the case as well as off the signup
// (both FKs cascade), so an operator refused at تسجيلات المهام could delete the
// case from الحالات and destroy exactly the same messages. Guarding one door
// and not the other is not a guard.
//
// beneficiary_case_documents is the second loss and it is specific to this
// route: the files a beneficiary uploaded as proof. The file itself stays on
// disk, but the row saying what it is, who uploaded it and which case it
// belongs to is destroyed, and there is nothing left to rebuild it from — an
// approved case would be restored from المهملات with its evidence gone.
//
// The operator's way out is POST /api/admin/beneficiary_cases/:id/status,
// whose allowed set already includes 'archived'.
func (h *AdminDeleteHandler) BeneficiaryCase(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	records, err := deleteguard.New(h.Pool).ForCase(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}
	if records.Any() {
		c.JSON(http.StatusConflict, gin.H{
			"success":   false,
			"code":      "case_has_records",
			"messages":  records.Messages,
			"documents": records.Documents,
			"error": "Cannot delete: this case has a chat conversation or uploaded documents, " +
				"and deleting it would permanently destroy them. Archive the case instead.",
		})
		return
	}
	trashRow(c, h.Pool, "beneficiary_cases", id)
}

// ProjectRequest deletes a beneficiary project request.
//
// The cascade takes beneficiary_project_request_comments and _likes. The
// comments are the loss worth refusing over: prose OTHER PEOPLE wrote on
// somebody else's request, destroyed without their authors doing anything.
//
// The likes are judged disposable and the guard deliberately ignores them — a
// like carries no authored content, no money and no evidence, it is one tap the
// same person can make again, and it is only ever shown as a total. Refusing
// over one would cost the operator the ability to remove a popular request
// while protecting nothing anybody could miss. See deleteguard.ProjectRequestRecords.
//
// The way out is POST /api/admin/beneficiary_project_requests/:id/status.
func (h *AdminDeleteHandler) ProjectRequest(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	records, err := deleteguard.New(h.Pool).ForProjectRequest(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}
	if records.Any() {
		c.JSON(http.StatusConflict, gin.H{
			"success":  false,
			"code":     "project_request_has_comments",
			"comments": records.Comments,
			"error": "Cannot delete: people have commented on this request, and deleting it " +
				"would permanently destroy their comments. Change its status instead.",
		})
		return
	}
	trashRow(c, h.Pool, "beneficiary_project_requests", id)
}

// Sponsorship deletes a sponsorship, refusing only when the schedule holds a
// SETTLED occurrence.
//
// This is the one route where most of the cascade is genuinely disposable, and
// the reasoning is the same shape as ee50aae's "messages, not threads":
// sponsorshipschedule.Generate materialises upcoming rows from the
// sponsorship's own recurrence rule, idempotently, so an unsettled occurrence
// is a projection that comes back by itself. A 'paid' or 'skipped' row is a
// decision somebody made about money on a date, and Generate never recreates
// it. Refusing on every schedule row would have blocked practically every
// active sponsorship for nothing; refusing on the settled ones protects the
// only part that cannot be rebuilt.
//
// The way out is POST /api/admin/sponsorships/:id/status ('cancelled',
// 'stopped', 'completed').
func (h *AdminDeleteHandler) Sponsorship(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}
	records, err := deleteguard.New(h.Pool).ForSponsorship(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}
	if records.Any() {
		c.JSON(http.StatusConflict, gin.H{
			"success":             false,
			"code":                "sponsorship_has_settled_schedule",
			"settled_occurrences": records.SettledOccurrences,
			"error": "Cannot delete: this sponsorship has settled schedule dates (paid or skipped), " +
				"and deleting it would permanently destroy that payment history. " +
				"Change its status instead.",
		})
		return
	}
	trashRow(c, h.Pool, "sponsorships", id)
}

func (h *AdminDeleteHandler) InKindDonation(c *gin.Context) { h.deleteRow(c, "in_kind_donations") }
func (h *AdminDeleteHandler) SupportTicket(c *gin.Context)  { h.deleteRow(c, "support_tickets") }
func (h *AdminDeleteHandler) Donation(c *gin.Context)       { h.deleteRow(c, "donations") }

// VolunteerApplication deletes a volunteer application — UNGUARDED, and that
// is a decision, not an oversight.
//
// The cascade is volunteer_application_availability: one row per day the
// applicant said they were free (day_of_week, time_from, time_to). It is not in
// the trash payload, so a restore returns the application with its per-day
// availability blank.
//
// WHY NO GUARD. A refusal here would have cost far more than it protected, and
// in exactly the way ee50aae warned about. The application form's primary
// availability input is the per-day picker (humanitarian's
// availability_schedule_picker.dart, posted as `availability_schedule`), so
// practically every modern application carries these rows — refusing on them
// would have made practically every application permanently undeletable, which
// is the "refuse on the mere existence of a child" mistake that fix was written
// to avoid.
//
// And what is at stake is not of that order. These four columns are the
// applicant's own restatable preference, entered on the same form as the parent
// row, belonging to nobody but them, carrying no authored prose, no money and
// no evidence — and re-collected in full by the next application they submit.
// That is a different kind of thing from a conversation, a wallet ledger or a
// payment record, and the remedy is deliberately not applied uniformly to all
// six cascades just because one remedy was available.
//
// It is not nothing, either. Capturing the child rows into the trash payload
// would make the restore faithful, and that is the option left open: it is the
// third remedy admin_trash.go's Restore makes expensive today, and it is
// recorded in VERIFICATION_REPORT.md rather than hidden here.
func (h *AdminDeleteHandler) VolunteerApplication(c *gin.Context) {
	h.deleteRow(c, "volunteer_applications")
}
func (h *AdminDeleteHandler) Campaign(c *gin.Context) { h.deleteRow(c, "campaigns") }

// User deletes an account — the widest cascade in the codebase, and the reason
// this route no longer goes straight to trashRow.
//
// THE CASCADE. Read out of the live database (pg_constraint, confdeltype='c'),
// not guessed from the migration files:
//
//	users
//	  ├─ chat_threads (donor_user_id / owner_user_id / initiated_by)
//	  │    └─ chat_messages, chat_reads
//	  ├─ marriage_chat_threads / staff_chat_threads / case_volunteer_chat_threads
//	  │    └─ …_messages, …_reads
//	  ├─ wallet_transactions               ← the money the account holds
//	  ├─ marriage_subscription_purchases   ← the record that they PAID
//	  └─ user_profiles, notification_preferences, role_permissions, …
//
// trashRow archives only the row it deletes, so all of that was destroyed
// outright and المهملات handed back the `users` row alone. One mis-click
// removed every conversation the person was part of and their whole wallet
// ledger, unrecoverably, while telling the operator the action was undoable.
//
// THE REMEDY, AND WHY IT IS A REFUSAL RATHER THAN A NEW SOFT-DELETE COLUMN.
// The soft delete already exists and is already in the dashboard:
// POST /api/admin/users/:id/archive flips account_status to 'archived',
// force-logs the account out, drops it out of every list the Users page shows
// by default, and can be undone by any tier holding users/archive without a
// Super-Admin. main.go describes it in those words — "the non-destructive
// alternative to Delete". So there is nothing to build and no column to add:
// the operator is told what would be lost and pointed at Archive, which is
// what they wanted in the first place.
//
// THE GUARD COUNTS RECORDS, NOT CHILDREN, and that distinction is the whole
// design — the same one ee50aae made when it counted messages instead of
// threads. Every account that has ever been used owns a user_profiles row and
// notification_preferences rows; refusing on the existence of a cascade child
// would have made every account permanently undeletable. What is counted is
// what cannot be reconstructed: messages, money, and payment.
//
// WHAT THIS DOES NOT DO. It does not change any foreign key. Making
// wallet_transactions and marriage_subscription_purchases RESTRICT rather than
// CASCADE would be a stronger, delete-strategy-independent guarantee, and it is
// argued in VERIFICATION_REPORT.md — but it is a destructive migration
// (drop-and-recreate of a live constraint) and is an owner decision, not a bug
// fix. Note that marriage_profiles.user_id is ALREADY ON DELETE RESTRICT, which
// is why in practice a user holding a subscription purchase is refused by
// Postgres before this guard is even relevant; the count is kept anyway, so the
// operator reads a sentence about the payment instead of an FK detail string.
func (h *AdminDeleteHandler) User(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}

	// deleteguard.Store is a stateless wrapper over the pool, so it is built
	// here rather than injected: there is no lifecycle to share, and a nil
	// field on this handler would be a silent way to lose the guard.
	records, err := deleteguard.New(h.Pool).ForUser(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}
	if records.Any() {
		// `code` is the stable key the dashboard translates through its
		// `error.*` namespace, so an Arabic operator reads Arabic; `error` is
		// the fallback for a client without that mapping. The three counts say
		// how much is at stake, which is what makes the refusal actionable.
		c.JSON(http.StatusConflict, gin.H{
			"success":                false,
			"code":                   "user_has_records",
			"messages":               records.Messages,
			"wallet_transactions":    records.WalletTransactions,
			"subscription_purchases": records.SubscriptionPurchases,
			"error": "Cannot delete: this account holds chat messages, wallet transactions or " +
				"subscription payments, and deleting it would permanently destroy them. " +
				"Archive the account instead.",
		})
		return
	}

	trashRow(c, h.Pool, "users", id)
}

// Phase 22 — mission delete CASCADEs signups via the FK (volunteer_mission_signups
// fk_volunteer_mission_signups_mission ON DELETE CASCADE). Volunteers who had
// joined won't get a notification on cascade; if you need that, use a status
// transition to 'cancelled' instead (fires notifications via the signup path).
func (h *AdminDeleteHandler) VolunteerMission(c *gin.Context) { h.deleteRow(c, "volunteer_missions") }

// VolunteerMissionSignup deletes ONE signup — a single volunteer's request to
// join one mission — as opposed to VolunteerMission above, which removes the
// mission and cascades every signup on it.
//
// E15 — the client asked تسجيلات المهام for a fixed five-action list
// (موافق/قبول/رفض/تراجع/حذف). The first four are status transitions that
// already existed on adminStatusH.MissionSignup; حذف had no route of any kind,
// so the dashboard's action menu had nothing it could call. This is that route,
// and it goes through trashRow like the other recoverable deletes rather than
// running a DELETE of its own: a signup is not a catalogue row — it carries the
// volunteer's own completion note and the hours they served — so pressing حذف on
// the wrong row has to be undoable from المهملات (H15's rule).
//
// THE CASCADE, AND WHY THIS ROUTE REFUSES INSTEAD OF DELETING.
//
// Deleting a signup cascades its conversation (migration 061):
//
//	volunteer_mission_signups
//	  └─ case_volunteer_chat_threads   (signup_id ... ON DELETE CASCADE)
//	       ├─ case_volunteer_chat_messages
//	       └─ case_volunteer_chat_reads
//
// trashRow snapshots only the row it deletes, so those children were destroyed
// outright and المهملات handed back the signup alone. That is worse than an
// unrecoverable delete with no Trash entry, because the operator has been told
// the action is undoable — they press حذف believing the conversation is safe.
//
// TWO WAYS TO FIX IT, AND WHY THIS ONE.
//
// (a) Archive the cascaded children into the trash payload so restore is
// faithful. Rejected. It turns trash_items from a flat row snapshot into a
// nested tree, and Restore — which admin_trash.go already flags as the place a
// mistake becomes "a worse bug than the one being fixed" — would have to
// re-insert three tables in FK order, remap identity keys, and cope with
// senders who were themselves deleted in the meantime. That is a new mechanism
// carrying the repo's most dangerous operation, built to make a rare admin
// action tidier.
//
// (b) Refuse the delete while there is a conversation to lose. Taken. It is
// the repo's existing vocabulary — trashRow already answers 409 when a row is
// still referenced — and it satisfies the actual requirement outright: a
// delete never silently destroys messages, because it never destroys them at
// all.
//
// THE TRADE-OFF. (b) buys safety with capability: a signup that has been
// talked about cannot be removed from تسجيلات المهام at all. That is a real
// cost and it is accepted deliberately, because the operator is not left
// stuck — رفض and تراجع are status transitions that already exist on this row
// and take it out of the working list without touching a message. What is
// lost is tidying; what is kept is the conversation. (a) remains open if the
// Trash ever grows a general tree-restore, and this refusal is forward
// compatible with it.
//
// This follows K14 (marriage/owner.go), which refused to route
// marriage_profiles through trashRow for the same reason — its cascade reaches
// chat threads and the record that the user PAID. The difference is the remedy:
// K14 needed the profile to disappear from a public browse feed, so it stamped
// a soft-delete. Nothing here needs to disappear, so no new column is needed.
//
// The guard counts MESSAGES, not threads, and that distinction is the whole
// design: casevolchat.EnsureThreadForSignup opens a thread the moment a signup
// with a linked case is approved, so refusing on thread existence would have
// made nearly every approved signup undeletable — a far bigger regression than
// the bug. An empty thread has no conversation to protect and re-opens by
// itself; see MessageCountForSignup.
func (h *AdminDeleteHandler) VolunteerMissionSignup(c *gin.Context) {
	id, ok := parseID(c)
	if !ok {
		return
	}

	// casevolchat.Store is a stateless wrapper over the pool, so it is built
	// here rather than injected: there is no lifecycle to share, and a nil
	// field on this handler would be a silent way to lose the guard.
	messages, err := casevolchat.New(h.Pool).MessageCountForSignup(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "Database error: " + err.Error(),
		})
		return
	}
	if messages > 0 {
		// `code` is the stable key the dashboard translates through its
		// `error.*` namespace, so an Arabic operator reads Arabic; `error` is
		// the fallback for a client without that mapping. `messages` says how
		// much is at stake, which is what makes the refusal actionable.
		c.JSON(http.StatusConflict, gin.H{
			"success":  false,
			"code":     "signup_has_chat_history",
			"messages": messages,
			"error": "Cannot delete: this signup has a chat conversation, and deleting it " +
				"would permanently destroy those messages. Use reject or withdraw instead.",
		})
		return
	}

	trashRow(c, h.Pool, "volunteer_mission_signups", id)
}
