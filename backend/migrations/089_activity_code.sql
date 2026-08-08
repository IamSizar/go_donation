-- 089 — "Post Information": an Activity Code identifying each Our Work post
-- and the category it belongs to (e.g. HUM-000123, EDU-000045).
--
-- Already satisfied elsewhere, NOT rebuilt here:
--   * Interaction options — post_likes (like toggle), post_comments and
--     media_posts.share_count already exist (migration 034).
--   * Comment management — post_comments carries a moderation status, the
--     banned_words blocklist is admin-managed and checked at submit time, and
--     admin routes already exist to list, restatus and delete comments.
--   * "Add new sections / activity types / edit / delete, no app update" —
--     media_categories is admin CRUD; group_key (migration 088) splits the
--     list into Humanitarian Assistance vs Other Programs.
--
-- The code's prefix comes from the post's category, so a new category
-- automatically gets its own code namespace with no code change — the
-- "create a new field automatically in the future" requirement.

-- Per-category prefix + running sequence. Both admin-editable, same shape as
-- donation_section_codes (migration 026), which does this for payments.
ALTER TABLE media_categories
  ADD COLUMN IF NOT EXISTS code_prefix VARCHAR(8)  NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS next_seq    BIGINT      NOT NULL DEFAULT 1;

-- Seed sensible prefixes. A category left with '' falls back to a generic
-- prefix at generation time, so an admin-added category still gets codes
-- immediately without having to set one first.
UPDATE media_categories SET code_prefix = 'HUM' WHERE group_key = 'humanitarian' AND code_prefix = '';
UPDATE media_categories SET code_prefix = 'EDU' WHERE slug IN ('education','education_training');
UPDATE media_categories SET code_prefix = 'WMN' WHERE slug = 'womens_programs';
UPDATE media_categories SET code_prefix = 'HER' WHERE slug = 'heritage_culture';
UPDATE media_categories SET code_prefix = 'CHD' WHERE slug = 'childhood';
UPDATE media_categories SET code_prefix = 'LIV' WHERE slug = 'livelihoods';
UPDATE media_categories SET code_prefix = 'ENV' WHERE slug = 'environment';
UPDATE media_categories SET code_prefix = 'PCE' WHERE slug = 'peacebuilding';
UPDATE media_categories SET code_prefix = 'EXH' WHERE slug = 'exhibitions';
UPDATE media_categories SET code_prefix = 'COM' WHERE slug = 'community_activities';
-- Anything still blank (e.g. a category added before this ran) gets ACT.
UPDATE media_categories SET code_prefix = 'ACT' WHERE code_prefix = '';

ALTER TABLE media_posts
  ADD COLUMN IF NOT EXISTS activity_code VARCHAR(64) NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_media_posts_activity_code
  ON media_posts(activity_code);
