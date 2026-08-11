-- 100 — Remaining fields from the City Guide and Product List specs.
--
-- 1. "Social media links, including Facebook, Instagram, and website."
--    city_directory_entries had `website` and nothing else, so a shop's
--    Facebook or Instagram page could not be stored at all. Kept as TEXT to
--    match partners.social_links, which already holds the same kind of value
--    in the same shape — one place, one convention.
ALTER TABLE city_directory_entries
  ADD COLUMN IF NOT EXISTS social_links TEXT;

-- 2. "Working hours, including Open Now/Closed status."
--    opening_hours is free text in four languages, which reads well and is
--    completely uncomputable — nothing can derive "open now" from
--    "9 صباحاً حتى 5 مساءً". This adds an optional machine-readable companion:
--
--      {"mon":[["09:00","17:00"]], "sat":[], ...}
--
--    A day mapped to [] is closed; a day absent means "unknown", which the app
--    renders as no badge rather than guessing. The free-text column stays and
--    is still what gets displayed — this only drives the badge, so an entry
--    nobody has filled in behaves exactly as it does today.
ALTER TABLE city_directory_entries
  ADD COLUMN IF NOT EXISTS hours JSONB;

-- 3. The sixth sector. The spec names six; only five existed, so every
--    heritage site, hotel, restaurant, park and sports club in Mosul had
--    nowhere to sit. Ordered last to leave the existing five where staff
--    already expect them.
INSERT INTO city_sectors (slug, name_en, name_ar, name_ckb, name_kmr, display_order, active)
VALUES ('tourism', 'Tourism, Heritage & Entertainment',
        'السياحة والتراث والترفيه', 'گەشتیاری، کەلەپوور و کاتبەسەربردن',
        'گەشتیاری، کەلەپوور و بۆرینا دەمی', 6, 1)
ON CONFLICT (slug) DO NOTHING;

-- 4. "Brands" is one of the functional list labels, but marketplace_products
--    had no brand column — so a Brands filter had nothing to filter on. SKU,
--    price, status, specs and the labels array already existed.
ALTER TABLE marketplace_products
  ADD COLUMN IF NOT EXISTS brand VARCHAR(120) NOT NULL DEFAULT '';

-- Brands are browsed as a filter ("show me everything by X"), which is a
-- lookup on a low-cardinality column across the active catalogue.
CREATE INDEX IF NOT EXISTS idx_marketplace_products_brand
  ON marketplace_products (brand)
  WHERE brand <> '';
