-- 133 — Store sections: admin-curated shelves with a cover image.
--
-- THE GAP THIS CLOSES
-- The client wants to group products into named, admin-curated shelves for
-- the storefront — e.g. "Clothing" — each with its own cover image, shown as
-- a rail above the catalogue. `marketplace_categories` (migration 028) is
-- close but wrong for this: a category is a single required tag on a product
-- (`marketplace_products.category_slug`) with no image, chosen by whoever
-- lists the product. A section is the opposite shape — an admin-only curated
-- collection that any number of already-existing products can be added to or
-- removed from without touching the product row itself, and a product can sit
-- in more than one section (e.g. a hoodie in both "Clothing" and "New This
-- Month"). That many-to-many, admin-owned relationship is what this migration
-- adds, alongside categories rather than replacing them.
--
-- TWO TABLES, MIRRORING marketplace_categories + a join table
-- `marketplace_sections` holds the shelf itself: name, cover image, an active
-- flag and an optional visibility window (start/end), display order for the
-- rail. `marketplace_section_products` is the join — composite PK so a
-- product can't be added to the same section twice, ON DELETE CASCADE both
-- ways so removing a section or a product cleans up its memberships for free,
-- and its own `added_at` so the admin UI can show a section in the order
-- products joined it if it ever wants to.
CREATE TABLE IF NOT EXISTS marketplace_sections (
  id                BIGSERIAL PRIMARY KEY,
  slug              VARCHAR(64) NOT NULL UNIQUE,
  name_en           TEXT        NOT NULL,
  name_ar           TEXT        NOT NULL DEFAULT '',
  name_ckb          TEXT        NOT NULL DEFAULT '',
  name_kmr          TEXT        NOT NULL DEFAULT '',
  -- Storage-relative path, same shape as marketplace_products.image_path —
  -- resolved through the same storage.Storage/assetUrl convention, not a new
  -- one.
  cover_image_path  TEXT        NOT NULL DEFAULT '',
  display_order     INTEGER     NOT NULL DEFAULT 0,
  active             SMALLINT   NOT NULL DEFAULT 1,
  -- Optional visibility window. Both NULL (the default) means "always shown
  -- while active" — most sections will never set these; they exist for a
  -- seasonal shelf the admin wants to schedule ahead of time and let expire
  -- without a follow-up click.
  starts_at         TIMESTAMP,
  ends_at           TIMESTAMP,
  created_at        TIMESTAMP   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMP   NOT NULL DEFAULT NOW(),
  created_by        BIGINT
);

CREATE TABLE IF NOT EXISTS marketplace_section_products (
  section_id  BIGINT NOT NULL REFERENCES marketplace_sections(id) ON DELETE CASCADE,
  product_id  BIGINT NOT NULL REFERENCES marketplace_products(id) ON DELETE CASCADE,
  added_at    TIMESTAMP NOT NULL DEFAULT NOW(),
  PRIMARY KEY (section_id, product_id)
);

-- Every public read of a section list filters `active` and orders by
-- display_order; every product-list-by-section join filters by product_id
-- for the reverse case (does a saved product still belong anywhere). One
-- index each covers both access paths.
CREATE INDEX IF NOT EXISTS idx_marketplace_sections_active_order
  ON marketplace_sections (active, display_order, id);
CREATE INDEX IF NOT EXISTS idx_marketplace_section_products_product
  ON marketplace_section_products (product_id);
