-- 142_marketplace_order_payment_method.sql
-- R2 #66 — a store order records HOW the buyer chose to pay, the same way a
-- donation does: the name of a method from the payment-methods catalogue
-- (cash, a bank account, a card, a mobile-balance number …) or 'app_wallet'.
-- Staff see it next to the order and approve the order once the payment has
-- been received, exactly as they confirm a donation.
--
-- Additive and defaulted: every existing order simply reads as "not recorded".
ALTER TABLE marketplace_orders
  ADD COLUMN IF NOT EXISTS payment_method VARCHAR(64) NOT NULL DEFAULT '';
