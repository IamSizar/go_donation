-- 010_phone_canonical.sql
-- Canonicalize every users.phone to the single DB form: leading "0" + the
-- 10-digit national number, e.g. "07508582031". This is the DB side of the
-- normalization that auth.NormalizePhone now enforces on input, so the same
-- person can never become two accounts by typing "750…" vs "0750…" vs "+964…".
--
-- canonical(phone) = '0' || ltrim( strip-country-code( digits-only(phone) ), '0' )
--
-- Because existing rows are a mix of "964…" and bare "750…", some collapse to
-- the same canonical value (notably the admin "9647508582031" and the donor
-- "7508582031" are the same person). For each colliding group we keep ONE
-- survivor (admins first, then lowest id), move its duplicates' data onto the
-- survivor, delete the duplicates, then rewrite all phones.
--
-- Idempotent: re-running is a no-op once every phone is already canonical and
-- no duplicates remain.

DO $$
DECLARE
  grp RECORD;
  survivor INT;
  loser INT;
BEGIN
  -- 1. Drop rows that don't reduce to a valid 10-digit national number AND
  --    carry no protected data. In this DB those are malformed test seeds.
  DELETE FROM users u
   WHERE length(ltrim(regexp_replace(regexp_replace(u.phone, '\D', '', 'g'), '^(00)?964', ''), '0')) <> 10
     AND NOT EXISTS (SELECT 1 FROM donations d WHERE d.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM sponsorships s WHERE s.donor_user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM marketplace_orders m WHERE m.buyer_user_id = u.id);

  -- 2. Merge duplicate-canonical groups into a single survivor.
  FOR grp IN
    SELECT canon, array_agg(id ORDER BY is_admin DESC, id ASC) AS ids
      FROM (
        SELECT id, is_admin,
               '0' || ltrim(regexp_replace(regexp_replace(phone, '\D', '', 'g'), '^(00)?964', ''), '0') AS canon
          FROM users
      ) x
     GROUP BY canon
    HAVING count(*) > 1
  LOOP
    survivor := grp.ids[1];
    FOREACH loser IN ARRAY grp.ids[2:array_length(grp.ids, 1)] LOOP
      -- Reassign data-bearing children (RESTRICT FKs MUST move before delete;
      -- SET NULL / CASCADE ones are moved too so the data survives the merge).
      UPDATE donations                    SET user_id        = survivor WHERE user_id        = loser;
      UPDATE sponsorships                  SET donor_user_id  = survivor WHERE donor_user_id  = loser;
      UPDATE marketplace_orders            SET buyer_user_id  = survivor WHERE buyer_user_id  = loser;
      UPDATE marketplace_products          SET seller_user_id = survivor WHERE seller_user_id = loser;
      UPDATE marriage_profiles             SET user_id        = survivor WHERE user_id        = loser;
      UPDATE beneficiary_project_requests  SET user_id        = survivor WHERE user_id        = loser;
      UPDATE beneficiary_cases             SET user_id        = survivor WHERE user_id        = loser;
      UPDATE in_kind_donations             SET donor_user_id  = survivor WHERE donor_user_id  = loser;
      UPDATE support_tickets               SET user_id        = survivor WHERE user_id        = loser;
      UPDATE volunteer_applications        SET user_id        = survivor WHERE user_id        = loser;
      UPDATE app_notifications             SET user_id        = survivor WHERE user_id        = loser;
      UPDATE campaigns                     SET owner_user_id  = survivor WHERE owner_user_id  = loser;

      -- user_profiles is one-row-per-user: keep the survivor's; move the
      -- loser's only if the survivor has none.
      IF EXISTS (SELECT 1 FROM user_profiles WHERE user_id = survivor) THEN
        DELETE FROM user_profiles WHERE user_id = loser;
      ELSE
        UPDATE user_profiles SET user_id = survivor WHERE user_id = loser;
      END IF;

      -- Everything else referencing the loser (tokens, devices, read receipts,
      -- audit rows, mission signups, comments/likes) is ephemeral and cascades
      -- / nulls on delete.
      DELETE FROM users WHERE id = loser;
    END LOOP;
  END LOOP;

  -- 3. Rewrite every remaining phone to canonical form.
  UPDATE users
     SET phone = '0' || ltrim(regexp_replace(regexp_replace(phone, '\D', '', 'g'), '^(00)?964', ''), '0')
   WHERE phone <> '0' || ltrim(regexp_replace(regexp_replace(phone, '\D', '', 'g'), '^(00)?964', ''), '0');
END $$;
