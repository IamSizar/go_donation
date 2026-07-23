-- Client note — Marriage "Subscription": replace the fixed 5-tier enum +
-- admin-settings prices with a real, dynamically admin-manageable packages
-- table (add/edit/reprice/reorder/delete), same CRUD shape already used for
-- payment methods — plus a purchase ledger so a paid subscription is a real,
-- auditable transaction rather than an admin manually flipping a field.
CREATE TABLE IF NOT EXISTS marriage_subscription_packages (
    id BIGSERIAL PRIMARY KEY,
    slug VARCHAR(64) UNIQUE NOT NULL,
    name_en VARCHAR(128) NOT NULL,
    name_ar VARCHAR(128) NOT NULL DEFAULT '',
    name_ckb VARCHAR(128) NOT NULL DEFAULT '',
    name_kmr VARCHAR(128) NOT NULL DEFAULT '',
    description_en TEXT NOT NULL DEFAULT '',
    description_ar TEXT NOT NULL DEFAULT '',
    description_ckb TEXT NOT NULL DEFAULT '',
    description_kmr TEXT NOT NULL DEFAULT '',
    price_iqd BIGINT NOT NULL DEFAULT 0,
    display_order INTEGER NOT NULL DEFAULT 0,
    active SMALLINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_marriage_subscription_packages_active
    ON marriage_subscription_packages (active, display_order);

-- Migrate the 5 existing tiers + whatever prices an admin already set (in
-- app_settings) so nothing already configured is lost.
INSERT INTO marriage_subscription_packages
    (slug, name_en, name_ar, name_ckb, name_kmr, price_iqd, display_order)
SELECT t.slug, t.name_en, t.name_ar, t.name_ckb, t.name_kmr,
       COALESCE((SELECT NULLIF(value, '')::bigint FROM app_settings
                  WHERE key = 'marriage_package_price_' || t.slug), 0),
       t.display_order
FROM (VALUES
    ('bronze',  'Bronze',  'برونزي', 'برۆنز',  'برۆنز',  1),
    ('silver',  'Silver',  'فضي',    'زیو',    'زیڤ',    2),
    ('gold',    'Gold',    'ذهبي',   'زێڕ',    'زێر',    3),
    ('diamond', 'Diamond', 'ماسي',   'ئەڵماس', 'ئەلماس', 4),
    ('vip',     'VIP',     'VIP',    'VIP',    'VIP',    5)
) AS t(slug, name_en, name_ar, name_ckb, name_kmr, display_order)
ON CONFLICT (slug) DO NOTHING;

-- subscription_status now stores a package slug rather than a fixed enum —
-- an admin adding/renaming/removing packages shouldn't require a schema
-- change every time.
ALTER TABLE marriage_profiles
    DROP CONSTRAINT IF EXISTS marriage_profiles_subscription_status_check;

CREATE TABLE IF NOT EXISTS marriage_subscription_purchases (
    id BIGSERIAL PRIMARY KEY,
    profile_id BIGINT NOT NULL REFERENCES marriage_profiles(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    package_id BIGINT NOT NULL REFERENCES marriage_subscription_packages(id),
    price_iqd BIGINT NOT NULL,
    -- 'app_wallet' or a payment_methods.slug (cash/bank/etc).
    payment_method VARCHAR(32) NOT NULL,
    -- Wallet payments are instant ('paid'); everything else stays 'pending'
    -- until staff confirms it — same shape as donations' payment_status.
    status VARCHAR(16) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_marriage_subscription_purchases_profile
    ON marriage_subscription_purchases (profile_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_marriage_subscription_purchases_status
    ON marriage_subscription_purchases (status, id DESC);
