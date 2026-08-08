-- 087 — Reclassify due-date reminders into the app's Reminder filter.
--
-- Background: notification categories are resolved by substring match, and
-- the "payment"/"sponsorship" branch used to run BEFORE the "reminder"/"due"
-- branch — so anything named *_due_* was filed as Payment. That made the
-- app's dedicated Reminder filter effectively unreachable for the one type
-- that most belonged in it.
--
-- The ordering is now fixed in both places that resolve a category:
--   * resolveCategory            (backend/internal/notify/notify.go)
--   * _categoryFromType          (app_notification_model.dart)
-- Both put reminder/due ahead of payment, and each carries a comment
-- pointing at the other so they stay in sync.
--
-- New notifications therefore get 'reminder' from now on. Existing rows keep
-- whatever was stored at write time — and the app prefers the stored value
-- over re-inferring — so without this backfill, reminders already in a user's
-- list would stay in Payment forever. This moves them across.
--
-- Scoped to the three due-date reminder types only; every other notification
-- keeps the category it was written with.
UPDATE app_notifications
   SET notification_category = 'reminder'
 WHERE notification_category <> 'reminder'
   AND notification_type IN (
         'sponsorship_payment_due_reminder',
         'sponsorship_due_grantor',
         'sponsorship_due_recipient'
       );
