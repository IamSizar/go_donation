-- 121_community_media_type.sql
-- OPOS #25272 — "City Guide" and "Community Services" turned out to be the
-- same feature (both read city_directory_entries) shown in two places, not
-- two distinct features. Community Services becomes its own real content: a
-- feed of community events/announcements staff post from the admin panel.
--
-- Reuses media_posts exactly the way 011_marriage_media.sql carved out
-- 'marriage': a new post_type value, same admin CRUD + /api/media?type=
-- filter, and excluded from the general news feed (no type filter) in Go so
-- the two feeds stay separate.

ALTER TABLE media_posts DROP CONSTRAINT IF EXISTS media_posts_post_type_check;
ALTER TABLE media_posts
  ADD CONSTRAINT media_posts_post_type_check
  CHECK (post_type::text = ANY (ARRAY[
    'news'::varchar, 'activity'::varchar, 'event'::varchar,
    'article'::varchar, 'video'::varchar, 'marriage'::varchar,
    'community'::varchar
  ]::text[]));
