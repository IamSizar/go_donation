-- 022_profession_order.sql
--
-- Section 13 — let the admin reorder custom professions in the skill dropdown.
-- `display_order` drives the list order (ties fall back to id). Existing rows
-- seed their order from their id so the current order is preserved.
ALTER TABLE custom_professions
  ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;

UPDATE custom_professions SET display_order = id WHERE display_order = 0;
