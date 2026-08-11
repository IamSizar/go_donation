-- 097 — Backfill Activity Codes for posts that predate migration 089.
--
-- 089 added media_posts.activity_code and the per-category prefix/sequence,
-- and the admin create path has issued a code for every post made since. What
-- it never did was populate the posts that already existed, so every post in
-- the system is uncoded — the Activity Code requirement is satisfied only for
-- content created after the migration ran.
--
-- Codes are issued here the same way NextActivityCode issues them: the
-- category's prefix (or ACT when it has none) plus a zero-padded number drawn
-- from that category's own sequence, so the backfilled codes and every future
-- code share one namespace and cannot collide.
--
-- Posts with no category get the generic ACT prefix and draw from a category
-- row of their own, because an uncategorised post still needs to be findable
-- by code. They are numbered from a single shared counter.

-- 1. Uncategorised posts need somewhere to draw a sequence from. A hidden
--    category row is the least invasive place: it is inactive, so it never
--    appears in the app's filter chips or the admin picker, but it gives the
--    existing NextActivityCode logic a prefix and counter to use.
INSERT INTO media_categories (slug, name_en, name_ar, name_ckb, name_kmr,
                              code_prefix, active, display_order)
VALUES ('uncategorised', 'Uncategorised', 'غير مصنّف', 'پۆلێننەکراو', 'نەپۆلاندی',
        'ACT', 0, 999)
ON CONFLICT (slug) DO NOTHING;

-- 2. Number the uncoded posts within each category, oldest first, so the
--    sequence reflects the order the activities actually happened.
WITH numbered AS (
  SELECT p.id,
         COALESCE(NULLIF(TRIM(p.category_slug), ''), 'uncategorised') AS cat,
         ROW_NUMBER() OVER (
           PARTITION BY COALESCE(NULLIF(TRIM(p.category_slug), ''), 'uncategorised')
           ORDER BY COALESCE(p.event_date::timestamp, p.created_at), p.id
         ) AS n
    FROM media_posts p
   WHERE COALESCE(TRIM(p.activity_code), '') = ''
),
-- Each post's number starts from wherever its category's counter already is,
-- so a category that has issued codes since 089 continues from there rather
-- than reusing numbers.
assigned AS (
  SELECT nm.id,
         COALESCE(NULLIF(c.code_prefix, ''), 'ACT') AS prefix,
         c.next_seq + nm.n - 1                      AS seq,
         nm.cat
    FROM numbered nm
    JOIN media_categories c ON c.slug = nm.cat
)
UPDATE media_posts p
   SET activity_code = a.prefix || '-' || LPAD(a.seq::text, 6, '0')
  FROM assigned a
 WHERE p.id = a.id;

-- 3. Move each category's counter past every code that now exists in it.
--    Derived from the codes themselves rather than from a count of what this
--    migration touched, so it is correct whether or not the create path has
--    already issued codes, and re-running it cannot double-advance.
UPDATE media_categories c
   SET next_seq = GREATEST(c.next_seq, m.max_seq + 1)
  FROM (
    SELECT COALESCE(NULLIF(TRIM(p.category_slug), ''), 'uncategorised') AS cat,
           MAX(SPLIT_PART(p.activity_code, '-', 2)::bigint)             AS max_seq
      FROM media_posts p
     WHERE p.activity_code ~ '^[A-Z]+-[0-9]+$'
     GROUP BY 1
  ) m
 WHERE c.slug = m.cat;
