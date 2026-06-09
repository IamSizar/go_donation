-- 011_marriage_media.sql
-- Allow media_posts to carry a "marriage" post_type. Marriage media posts are
-- regular media_posts (same 4-language title/body, media_url, status) tagged
-- post_type='marriage' so they reuse the existing admin CRUD + /media?type=
-- filter. The general news feed (no type filter) excludes 'marriage' in Go, so
-- the two stay separate.

ALTER TABLE media_posts DROP CONSTRAINT IF EXISTS media_posts_post_type_check;
ALTER TABLE media_posts
  ADD CONSTRAINT media_posts_post_type_check
  CHECK (post_type::text = ANY (ARRAY[
    'news'::varchar, 'activity'::varchar, 'event'::varchar,
    'article'::varchar, 'video'::varchar, 'marriage'::varchar
  ]::text[]));
