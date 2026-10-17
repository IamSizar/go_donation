-- 144 — short, sequential section codes (client note on identifying codes).
--
-- One letter per section family, taken from the word TAWAZN, followed by a
-- running number: Z1, Z2, Z3 … instead of CAM-000042 / COP00102. Accounts keep
-- T (already in place). Sections that share a letter share ONE counter, so a
-- code is never issued twice.
--
--   Z  every donation kind (general, campaign, sponsorship, in-kind, operational)
--   N  shop purchases
--   A  marriage (family files and subscription payments)
--   W  everything else: Our Work posts, projects, achievements
--
-- Codes already issued are left exactly as they are; only new ones are short.
-- The letter stays editable from the donation-codes screen.
CREATE TABLE IF NOT EXISTS code_sequences (
  prefix   VARCHAR(16) PRIMARY KEY,
  next_seq BIGINT      NOT NULL DEFAULT 1
);

UPDATE donation_section_codes SET prefix = 'Z'
 WHERE kind IN ('general', 'campaign', 'sponsorship', 'in_kind', 'operational');
UPDATE donation_section_codes SET prefix = 'N' WHERE kind = 'products';
UPDATE donation_section_codes SET prefix = 'A' WHERE kind = 'marriage';
UPDATE donation_section_codes SET prefix = 'W' WHERE kind IN ('projects', 'achievements');

UPDATE media_categories SET code_prefix = 'W';

INSERT INTO code_sequences (prefix) VALUES ('Z'), ('N'), ('A'), ('W')
ON CONFLICT (prefix) DO NOTHING;
