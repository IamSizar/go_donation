-- 084 — "Sixth/Seventh: Donations Page" specs (they overlap; this covers the
-- union of both).
--
-- Already implemented, NOT rebuilt here:
--   * Per-section Transaction Codes with admin-editable prefixes and an
--     independent gapless sequence — donation_section_codes (migration 026)
--     + internal/sectioncodes (NextReference issues e.g. GEN-000042).
--   * Notification on arrival: in-app via notify.DonationSubmittedMsg, plus an
--     SMS to the section's assigned phone carrying amount + code + section —
--     donation_section_codes.notify_phone/notify_enabled (migration 027) and
--     donations.notifySectionArrival.
--   * Cash donation (direct delivery) — payment_methods 'cash' (migration 030).
--
-- Gaps this migration closes:
--   1. Code namespaces existed only for donation_kinds. The specs also name
--      Our Products, My Engagement/Marriage, Projects and Our Achievements —
--      those payment surfaces had no Transaction Code and no section contact.
--   2. Donation types: electronic payment methods (Visa/MasterCard/e-wallets)
--      and mobile balance transfer (recharge cards / direct transfer) were not
--      offered. "Any other payment methods added in the future" stays covered
--      by payment_methods being an admin-managed table.

-- 1. New Transaction-Code namespaces. Prefixes and the per-section notify
--    phone are editable from the Admin Dashboard like the existing ones.
INSERT INTO donation_section_codes (kind, prefix) VALUES
  ('products',     'PRD'),
  ('marriage',     'MRG'),
  ('projects',     'PRJ'),
  ('achievements', 'ACH')
ON CONFLICT (kind) DO NOTHING;

-- 2. Carry the Transaction Code on the two other payment surfaces so every
--    payment is traceable and searchable from the Admin Panel.
ALTER TABLE marketplace_orders
  ADD COLUMN IF NOT EXISTS transaction_code VARCHAR(64) NOT NULL DEFAULT '';
ALTER TABLE marriage_subscription_purchases
  ADD COLUMN IF NOT EXISTS transaction_code VARCHAR(64) NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_marketplace_orders_txn
  ON marketplace_orders(transaction_code);
CREATE INDEX IF NOT EXISTS idx_marriage_purchases_txn
  ON marriage_subscription_purchases(transaction_code);
-- donations.reference_number holds the same kind of code; index it for the
-- Admin Panel's "search for any transaction" requirement.
CREATE INDEX IF NOT EXISTS idx_donations_reference
  ON donations(reference_number);

-- 3. Donation types. method_type has no CHECK constraint (migration 030), so
--    'card' and 'mobile' extend the existing cash/bank/wallet set freely.
INSERT INTO payment_methods
  (slug, method_type, name_en, name_ar, name_ckb, name_kmr,
   instructions_en, instructions_ar, instructions_ckb, instructions_kmr,
   account_number, display_order) VALUES
  ('mastercard', 'card', 'MasterCard', 'ماستركارد', 'ماستەرکارد', 'ماستەرکارد',
   'Pay by MasterCard.', 'ادفع باستخدام ماستركارد.',
   'بە ماستەرکارد پارە بدە.', 'ب ماستەرکاردێ پارە بدە.', '', 10),
  ('visa', 'card', 'Visa Card', 'فيزا كارد', 'ڤیزا کارد', 'ڤیزا کارد',
   'Pay by Visa card.', 'ادفع باستخدام بطاقة فيزا.',
   'بە کارتی ڤیزا پارە بدە.', 'ب کارتا ڤیزایێ پارە بدە.', '', 11),
  ('e_wallet', 'wallet', 'Electronic wallet', 'محفظة إلكترونية',
   'جزدانی ئەلیکترۆنی', 'جزدانێ ئەلیکترۆنی',
   'Pay from a supported electronic wallet.', 'ادفع من محفظة إلكترونية مدعومة.',
   'لە جزدانێکی ئەلیکترۆنیی پشتگیریکراو پارە بدە.',
   'ژ جزدانەکێ ئەلیکترۆنی یێ پشتەڤانیکری پارە بدە.', '', 12),
  ('mobile_recharge', 'mobile', 'Mobile recharge card', 'كارت شحن الموبايل',
   'کارتی پڕکردنەوەی مۆبایل', 'کارتا پرکرنا موبایلی',
   'Send the recharge card code.', 'أرسل رمز كارت الشحن.',
   'کۆدی کارتی پڕکردنەوە بنێرە.', 'کۆدێ کارتا پرکرنێ بنێرە.', '', 13),
  ('mobile_transfer', 'mobile', 'Mobile balance transfer', 'تحويل رصيد الموبايل',
   'گواستنەوەی باڵانسی مۆبایل', 'گوهاستنا بالانسێ موبایلی',
   'Transfer balance to the designated number.', 'حوّل الرصيد إلى الرقم المخصص.',
   'باڵانس بۆ ژمارەی دیاریکراو بگوازەوە.', 'بالانسی بۆ ژمارا دیارکری بگوهێزە.', '', 14)
ON CONFLICT (slug) DO NOTHING;
