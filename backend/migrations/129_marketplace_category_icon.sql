-- 129 — Store icon grid (#41080). Adds an admin-picked icon to each
-- marketplace category so the app can render a "food / accessories / ..."
-- icon grid instead of only a text filter chip.
--
-- icon_key is a fixed vocabulary rather than a free-text field or an
-- uploaded image: the app ships a client-side icon_key -> Material icon
-- lookup (see event_hub_cards.dart's analogous pattern for Events), so an
-- unrecognised key would render as nothing. The CHECK constraint keeps the
-- admin dropdown and the app's lookup table in lockstep — add a value to
-- both sides together, never just one.
ALTER TABLE marketplace_categories
  ADD COLUMN IF NOT EXISTS icon_key VARCHAR(32) NOT NULL DEFAULT 'other';

ALTER TABLE marketplace_categories DROP CONSTRAINT IF EXISTS marketplace_categories_icon_key_check;
ALTER TABLE marketplace_categories ADD CONSTRAINT marketplace_categories_icon_key_check
  CHECK (icon_key IN (
    'food', 'groceries', 'clothing', 'accessories', 'electronics', 'home',
    'beauty', 'toys', 'books', 'health', 'sports', 'tools', 'gifts', 'pets',
    'stationery', 'other'
  ));

-- Best-effort icons for the categories that already exist in every
-- environment (seeded by 036/099) so the grid isn't all "other" on first
-- deploy. Purely cosmetic and idempotent — an admin can repick any of these
-- from the dashboard afterward, and a slug this doesn't recognise just keeps
-- its default 'other'.
UPDATE marketplace_categories SET icon_key = CASE slug
  WHEN 'clothing' THEN 'clothing'
  WHEN 'food' THEN 'food'
  WHEN 'furniture' THEN 'home'
  WHEN 'electronics' THEN 'electronics'
  WHEN 'appliances' THEN 'home'
  WHEN 'kitchenware' THEN 'home'
  WHEN 'kids' THEN 'toys'
  WHEN 'footwear' THEN 'clothing'
  WHEN 'medical' THEN 'health'
  WHEN 'tools' THEN 'tools'
  WHEN 'books' THEN 'books'
  WHEN 'electronics_appliances' THEN 'electronics'
  WHEN 'fashion_clothing' THEN 'clothing'
  WHEN 'health_beauty' THEN 'beauty'
  WHEN 'home_garden' THEN 'home'
  WHEN 'food_beverages' THEN 'food'
  WHEN 'sports_fitness' THEN 'sports'
  WHEN 'kids_baby' THEN 'toys'
  WHEN 'automotive' THEN 'tools'
  WHEN 'books_stationery' THEN 'stationery'
  WHEN 'industrial_tools' THEN 'tools'
  ELSE icon_key
END
WHERE icon_key = 'other';
