-- 134 — Store overhaul: one section per product, categories archived.
--
-- THE CHANGE
-- The client's next request replaces marketplace_categories as the shopper-
-- facing grouping entirely: the store's product categories are gone from the
-- UI, and every product now belongs to at most ONE store section (or none,
-- and shows in the unsectioned shelf) — not several, the way migration 133's
-- many-to-many briefly allowed. That table shipped hours earlier in this same
-- project and was never used by a live client, so this is a straight
-- redesign, not a data-loss migration: nothing production depended on the
-- join table's shape.
--
-- `section_id` sits directly on marketplace_products, exactly like the old
-- `category_slug` did — one nullable FK, ON DELETE SET NULL so deleting a
-- section un-groups its products instead of deleting them.
ALTER TABLE marketplace_products
  ADD COLUMN IF NOT EXISTS section_id BIGINT REFERENCES marketplace_sections(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_marketplace_products_section
  ON marketplace_products (section_id);

DROP TABLE IF EXISTS marketplace_section_products;

-- CATEGORIES ARE ARCHIVED, NOT DELETED — client may want them back later.
-- marketplace_categories (table, admin CMS, routes) and marketplace_products.
-- category_slug are left exactly as they are: still readable, still
-- writable if anything ever sends them again, just no longer surfaced in the
-- app's UI or the admin product form. Nothing here drops them.
