-- 109 — K15: the product list's six functional labels had nothing to run on.
--
-- THE GAP THIS CLOSES
-- The client's product-list spec names six functional labels —
-- الأكثر مبيعاً (best selling), وصل حديثاً (new arrivals),
-- العروض والخصومات (offers and discounts), التصفية (filter),
-- الفئات (categories), العلامات التجارية (brands) — and zero of them worked.
--
-- The reason was entirely server-side. marketplace.Store.ListProducts took
-- (ctx, page, limit) and nothing else, ended `ORDER BY id DESC`, and did not
-- even SELECT created_at. So a chip built in the app could only have re-sorted
-- the twenty rows of the page it was already holding: "الأكثر مبيعاً" would
-- have been a claim about the catalogue backed by a slice of one page, which is
-- a lie rather than a feature. Four of the six needed nothing but query
-- parameters; two needed storage that did not exist:
--
--   الأكثر مبيعاً   — an order-count aggregate. Data existed
--                     (marketplace_orders.quantity); nothing aggregated it.
--   وصل حديثاً      — a created_at sort. Column existed; never selected, never
--                     ordered on, never indexed.
--   العروض والخصومات — A DISCOUNT AMOUNT. Nothing of the kind existed. The
--                     labels array has a 'sale' badge (migration 036) but a
--                     badge carries no number, so a discounts view could say
--                     "on sale" and could not say what the price now is.
--   التصفية         — price/availability parameters. Columns existed.
--   الفئات          — category_slug filter. Column and index existed (036).
--   العلامات التجارية — brand filter. Column and index existed (100) — but the
--                     column was never written by any code path and never
--                     selected by any query (see below).
--
-- This migration adds only what was genuinely missing: the discount amount, and
-- the indexes for the sorts and filters that now run over the whole catalogue
-- rather than over one page.
--
-- ADDITIVE ONLY
-- One new nullable column and four new indexes. No column is dropped, no type
-- changed, no existing value rewritten, and there is NO BACKFILL — NULL means
-- "no discount", which is exactly how every product in the catalogue behaves
-- today. Applying or reversing this migration changes no product's price.

-- ─── The discount amount ────────────────────────────────────────────────────
-- Stored as a whole percentage rather than a second price column, for two
-- reasons. It survives a price change (a 20% offer stays 20% off when the base
-- price is edited, where a hardcoded sale_price would quietly become a wrong
-- discount), and it is what the app has to print next to the product anyway.
--
-- NULL = not discounted. The CHECK refuses 0 as well as 100 so there is exactly
-- ONE representation of "no offer" (NULL) — a 0 stored here would put a product
-- in the العروض feed advertising a discount of nothing.
--
-- Deliberately NOT made NOT NULL DEFAULT 0: that would need a backfill, and it
-- would make "never set" and "explicitly zero" indistinguishable.
ALTER TABLE marketplace_products
  ADD COLUMN IF NOT EXISTS discount_percent SMALLINT;

DO $$
BEGIN
  ALTER TABLE marketplace_products
    ADD CONSTRAINT marketplace_products_discount_percent_check
    CHECK (discount_percent IS NULL OR (discount_percent > 0 AND discount_percent < 100));
EXCEPTION
  WHEN duplicate_object THEN NULL; -- already applied; this migration is idempotent
END $$;

-- ─── Indexes for the sorts and filters ──────────────────────────────────────
-- Every index below is partial on `status = 'approved'`, because the public
-- catalogue query is the only thing that sorts or filters on these columns and
-- it always carries that predicate. The dashboard's own product list (all
-- statuses) still orders by id, which the primary key already serves.

-- وصل حديثاً. Without this, "newest first" is a full sort of the approved
-- catalogue on every page request. id DESC is carried in the index as the
-- tiebreaker so the ORDER BY matches it exactly and Postgres can stop at LIMIT
-- instead of sorting the whole set.
CREATE INDEX IF NOT EXISTS idx_marketplace_products_new
  ON marketplace_products (created_at DESC, id DESC)
  WHERE status = 'approved';

-- العروض والخصومات. Highly selective — most products are not discounted — so a
-- partial index keeps the offers feed a lookup rather than a scan, and costs
-- nothing on writes to the undiscounted majority (a NULL row is not in it).
CREATE INDEX IF NOT EXISTS idx_marketplace_products_discount
  ON marketplace_products (discount_percent)
  WHERE discount_percent IS NOT NULL;

-- التصفية. Price is both a filter (min/max range) and two of the sort options
-- (price_asc / price_desc), which is exactly the pattern a btree serves.
CREATE INDEX IF NOT EXISTS idx_marketplace_products_price
  ON marketplace_products (price)
  WHERE status = 'approved';

-- The label filter (`labels @> ARRAY['sale']` and friends). labels is a TEXT[],
-- so containment needs GIN; a btree on an array column cannot answer it. Not
-- partial: GIN does not benefit from the status predicate here and the whole
-- array column is small.
CREATE INDEX IF NOT EXISTS idx_marketplace_products_labels
  ON marketplace_products USING GIN (labels);

-- NO NEW INDEX FOR الأكثر مبيعاً, DELIBERATELY.
-- Best-selling is SUM(quantity) GROUP BY product_id over marketplace_orders,
-- which reads every qualifying order row whatever indexes exist — a grouped
-- aggregate with no selective predicate cannot be turned into a lookup. The
-- one index that helps is the join back to products by product_id, and
-- idx_marketplace_orders_product (migration 001) already provides it. Adding a
-- second index here would be paid for on every order and never used.
--
-- ─── DOWN (reversal) ───────────────────────────────────────────────────────
-- This repo's runner (internal/db/migrate.go) is forward-only and records each
-- file in schema_migrations; there is no .down.sql convention, so the reversal
-- is recorded here and was EXECUTED against a local database before this
-- migration was committed:
--
--   DROP INDEX IF EXISTS idx_marketplace_products_labels;
--   DROP INDEX IF EXISTS idx_marketplace_products_price;
--   DROP INDEX IF EXISTS idx_marketplace_products_discount;
--   DROP INDEX IF EXISTS idx_marketplace_products_new;
--   ALTER TABLE marketplace_products
--     DROP CONSTRAINT IF EXISTS marketplace_products_discount_percent_check;
--   ALTER TABLE marketplace_products DROP COLUMN IF EXISTS discount_percent;
--   DELETE FROM schema_migrations WHERE version = '109_marketplace_catalogue_filters.sql';
--
-- Reversing discards any discount an admin had entered and returns every
-- product to its full price, which is the pre-migration behaviour. Nothing
-- else is affected: no existing column is read or written by this file, so
-- names, prices, stock, categories and labels survive a down-and-up cycle
-- untouched.
