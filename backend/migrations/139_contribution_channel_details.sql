-- 139 — R2 #47–55: the donation flow is now one fixed page per way of giving
-- (electronic payment, balance transfer, direct cash, in-kind). Each page asks
-- for details the donations table had nowhere to keep, so a donor's card
-- serial, network or transfer screenshot was either dropped or squeezed into
-- the free-text message.
--
-- `channel` is how the gift arrives: electronic | balance_transfer | cash.
-- (In-kind gifts live in in_kind_donations and do not come through here.)
-- `transfer_kind` splits the balance-transfer page's two toggles:
--   transfer = direct transfer / top-up to the organization's number,
--   card     = a recharge card sent as a photo + serial.
ALTER TABLE donations
  ADD COLUMN IF NOT EXISTS channel          VARCHAR(24),
  ADD COLUMN IF NOT EXISTS transfer_kind    VARCHAR(16),
  ADD COLUMN IF NOT EXISTS network          VARCHAR(32),
  ADD COLUMN IF NOT EXISTS serial_number    VARCHAR(64),
  ADD COLUMN IF NOT EXISTS attachment_path  TEXT,
  ADD COLUMN IF NOT EXISTS donor_phone      VARCHAR(32),
  ADD COLUMN IF NOT EXISTS donor_address    TEXT,
  ADD COLUMN IF NOT EXISTS visit_note       TEXT,
  ADD COLUMN IF NOT EXISTS currency         VARCHAR(8) NOT NULL DEFAULT 'IQD';

-- In-kind: the donor's phone and an optional photo of the items.
ALTER TABLE in_kind_donations
  ADD COLUMN IF NOT EXISTS donor_phone VARCHAR(32),
  ADD COLUMN IF NOT EXISTS photo_path  TEXT;
