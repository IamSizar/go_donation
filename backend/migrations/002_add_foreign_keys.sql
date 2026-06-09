-- Phase 17: add foreign key constraints that were missing from the MySQL dump.
--
-- The original dump (loaded via 001_full_v2.sql) carried almost no FKs — only 5,
-- all on the project-request comments/likes tables. As of Phase 13 admins can
-- DELETE rows, and without FKs they silently orphan child data: deleting a
-- beneficiary case leaves dangling sponsorships, marketplace products, etc.
--
-- This migration adds the FKs that should have been there all along. Every
-- constraint chooses one of three ON DELETE behaviours:
--
--   RESTRICT  — parent cannot be deleted while children exist. Backend's
--               existing 23503 → 409 handler in admin_delete.go will fire,
--               telling the admin which table is blocking.
--   SET NULL  — child survives without the parent (e.g. an audit row should
--               outlive the user it describes; an orphan donation still has
--               its amount and date).
--   CASCADE   — child has no meaning without parent (e.g. a device token
--               without a user, a user_profile row).
--
-- Before applying, a separate query confirmed there are zero orphan rows for
-- every relationship below — so adding the FKs cannot fail on existing data.
--
-- Apply with: psql ... -f migrations/002_add_foreign_keys.sql

BEGIN;

-- ============================================================
-- users — parent of almost everything
-- ============================================================

-- Profiles & device records: belong to the user. Delete the user → drop these.
ALTER TABLE user_profiles
  ADD CONSTRAINT fk_user_profiles_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE user_device_tokens
  ADD CONSTRAINT fk_user_device_tokens_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE api_access_tokens
  ADD CONSTRAINT fk_api_access_tokens_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Notifications are per-user; nothing to preserve if user is gone.
ALTER TABLE app_notifications
  ADD CONSTRAINT fk_app_notifications_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE app_notification_devices
  ADD CONSTRAINT fk_app_notification_devices_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE app_notification_reads
  ADD CONSTRAINT fk_app_notification_reads_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE app_notification_reads
  ADD CONSTRAINT fk_app_notification_reads_notification
  FOREIGN KEY (notification_id) REFERENCES app_notifications(id) ON DELETE CASCADE;

-- Profile audit logs follow the user record.
ALTER TABLE user_profile_audit_logs
  ADD CONSTRAINT fk_user_profile_audit_logs_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE user_profile_audit_logs
  ADD CONSTRAINT fk_user_profile_audit_logs_actor
  FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- Generic admin audit log: preserve history when the subject is deleted.
ALTER TABLE audit_log
  ADD CONSTRAINT fk_audit_log_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

-- Marriage profile cannot exist without its owner.
ALTER TABLE marriage_profiles
  ADD CONSTRAINT fk_marriage_profiles_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;

-- Donations: protect donor (RESTRICT) so we can't accidentally erase the
-- audit trail of who paid; campaign reference is best-effort (SET NULL).
ALTER TABLE donations
  ADD CONSTRAINT fk_donations_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE donations
  ADD CONSTRAINT fk_donations_campaign
  FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE SET NULL;

-- ============================================================
-- beneficiary_cases — central parent of several child tables
-- ============================================================

ALTER TABLE beneficiary_cases
  ADD CONSTRAINT fk_beneficiary_cases_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE beneficiary_cases
  ADD CONSTRAINT fk_beneficiary_cases_reviewed_by
  FOREIGN KEY (reviewed_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- Documents belong to the case.
ALTER TABLE beneficiary_case_documents
  ADD CONSTRAINT fk_beneficiary_case_documents_case
  FOREIGN KEY (case_id) REFERENCES beneficiary_cases(id) ON DELETE CASCADE;
ALTER TABLE beneficiary_case_documents
  ADD CONSTRAINT fk_beneficiary_case_documents_uploader
  FOREIGN KEY (uploaded_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- ============================================================
-- beneficiary_project_requests
-- ============================================================

ALTER TABLE beneficiary_project_requests
  ADD CONSTRAINT fk_bpr_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;

-- ============================================================
-- marketplace
-- ============================================================

ALTER TABLE marketplace_products
  ADD CONSTRAINT fk_marketplace_products_seller
  FOREIGN KEY (seller_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE marketplace_products
  ADD CONSTRAINT fk_marketplace_products_case
  FOREIGN KEY (beneficiary_case_id) REFERENCES beneficiary_cases(id) ON DELETE SET NULL;

-- Orders RESTRICT both ways — protect the audit trail.
ALTER TABLE marketplace_orders
  ADD CONSTRAINT fk_marketplace_orders_product
  FOREIGN KEY (product_id) REFERENCES marketplace_products(id) ON DELETE RESTRICT;
ALTER TABLE marketplace_orders
  ADD CONSTRAINT fk_marketplace_orders_buyer
  FOREIGN KEY (buyer_user_id) REFERENCES users(id) ON DELETE RESTRICT;

-- ============================================================
-- sponsorships — keep them tied to the case/request they fund
-- ============================================================

ALTER TABLE sponsorships
  ADD CONSTRAINT fk_sponsorships_donor
  FOREIGN KEY (donor_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE sponsorships
  ADD CONSTRAINT fk_sponsorships_case
  FOREIGN KEY (beneficiary_case_id) REFERENCES beneficiary_cases(id) ON DELETE RESTRICT;
ALTER TABLE sponsorships
  ADD CONSTRAINT fk_sponsorships_project_request
  FOREIGN KEY (project_request_id) REFERENCES beneficiary_project_requests(id) ON DELETE RESTRICT;

-- ============================================================
-- support / in-kind / volunteers
-- ============================================================

ALTER TABLE support_tickets
  ADD CONSTRAINT fk_support_tickets_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE in_kind_donations
  ADD CONSTRAINT fk_in_kind_donations_donor
  FOREIGN KEY (donor_user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE volunteer_applications
  ADD CONSTRAINT fk_volunteer_applications_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE volunteer_mission_signups
  ADD CONSTRAINT fk_volunteer_mission_signups_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE volunteer_mission_signups
  ADD CONSTRAINT fk_volunteer_mission_signups_mission
  FOREIGN KEY (mission_id) REFERENCES volunteer_missions(id) ON DELETE CASCADE;

-- ============================================================
-- media
-- ============================================================

ALTER TABLE media_posts
  ADD CONSTRAINT fk_media_posts_created_by
  FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- ============================================================
-- financial_expenses — bookkeeping should survive parent deletes
-- ============================================================

ALTER TABLE financial_expenses
  ADD CONSTRAINT fk_financial_expenses_case
  FOREIGN KEY (related_case_id) REFERENCES beneficiary_cases(id) ON DELETE SET NULL;
ALTER TABLE financial_expenses
  ADD CONSTRAINT fk_financial_expenses_project_request
  FOREIGN KEY (related_project_request_id) REFERENCES beneficiary_project_requests(id) ON DELETE SET NULL;
ALTER TABLE financial_expenses
  ADD CONSTRAINT fk_financial_expenses_created_by
  FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL;

COMMIT;
