-- Migration 008 — Structured volunteer skills + per-day availability
--
-- Phase 26: previously `skill_tags` was a free-form comma-separated TEXT
-- column and `availability` was a single text blob. We now want:
--   1. skill_tags as a proper TEXT[] aligned with a fixed 28-key catalogue
--      so the admin SPA can filter ("show all approved drivers in Duhok")
--      and the volunteer mobile form can render localized chips.
--   2. A separate per-day availability table so we can answer "who is free
--      on Wednesday afternoon?" in plain SQL without parsing free text.
--
-- The legacy `skills` (free-form description) and `availability` (free-form
-- text like "Mon/Wed/Fri afternoons") columns are kept untouched for
-- back-compat — they continue to mirror what the volunteer typed in the
-- catch-all "experience / other" textarea, and admin still sees them on
-- the application row. The new structured columns are additive.

BEGIN;

-- ---------- 1. skill_tags: TEXT → TEXT[] ----------
-- Rename the old free-form column first so we can rebuild it as an array
-- without dropping any existing data.
ALTER TABLE volunteer_applications
  RENAME COLUMN skill_tags TO skill_tags_legacy;

ALTER TABLE volunteer_applications
  ADD COLUMN skill_tags TEXT[] NOT NULL DEFAULT '{}';

-- Backfill 1/2: split the legacy CSV into a clean array. Only values that
-- match one of the 28 canonical keys make it through; anything else is
-- dropped (it would never match the SPA filter chip set anyway).
WITH known_keys AS (
  SELECT unnest(ARRAY[
    -- transport
    'driver_car','driver_truck','motorcycle',
    -- trades
    'electrician','plumber','carpenter','mason','mechanic',
    -- medical
    'first_aid','nurse','doctor','mental_health','eldercare',
    -- service
    'cook','cleaner','tailor',
    -- office/digital
    'designer','photographer','videographer','social_media','it_support','data_entry',
    -- teaching/language
    'teacher','translator_ar','translator_en','counselor',
    -- field work
    'distribution','survey','logistics','warehouse'
  ]) AS key
),
expanded AS (
  SELECT
    va.id,
    trim(unnest(string_to_array(coalesce(va.skill_tags_legacy, ''), ','))) AS raw_key
  FROM volunteer_applications va
)
UPDATE volunteer_applications va
SET skill_tags = sub.keys
FROM (
  SELECT id, array_agg(DISTINCT raw_key) AS keys
  FROM expanded
  WHERE raw_key IN (SELECT key FROM known_keys)
  GROUP BY id
) sub
WHERE va.id = sub.id;

-- Backfill 2/2: best-effort match against the free-form `skills` text using
-- multilingual keywords (EN/AR/Sorani/Badini). We only ADD keys that
-- aren't already present from step 1. The matcher is intentionally loose
-- — false positives here are cheap (admin can edit) but missing a real
-- driver is annoying.
WITH detected AS (
  SELECT
    va.id,
    -- transport
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(driver|sho?fer|ڕێبەر|شۆفێر|شوفير|سائق)' THEN 'driver_car' END AS k1,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(truck|شاحنة|لۆری|پاکپ)' THEN 'driver_truck' END AS k2,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(motorcycle|motor|دراجة|موتۆر)' THEN 'motorcycle' END AS k3,
    -- trades
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(electric|كهربا|کارەبا)' THEN 'electrician' END AS k4,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(plumb|سباك|لوله|بۆری)' THEN 'plumber' END AS k5,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(carpenter|نجار|دارتاش)' THEN 'carpenter' END AS k6,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(mason|builder|بناء|بەنا)' THEN 'mason' END AS k7,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(mechanic|ميكانيكي|میکانیکی)' THEN 'mechanic' END AS k8,
    -- medical
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(first aid|إسعاف|يارمەتی)' THEN 'first_aid' END AS k9,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(nurse|ممرض|پەرستار)' THEN 'nurse' END AS k10,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(doctor|طبيب|پزیشک|دکتۆر)' THEN 'doctor' END AS k11,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(mental|نفسي|دەروونی|psycho)' THEN 'mental_health' END AS k12,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(elder|مسن|پیر)' THEN 'eldercare' END AS k13,
    -- service
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(cook|طبخ|طاهي|چێشت)' THEN 'cook' END AS k14,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(clean|نظاف|پاک)' THEN 'cleaner' END AS k15,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(tailor|خياط|خەیات)' THEN 'tailor' END AS k16,
    -- office/digital
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(design|تصميم|دیزاین|graphic)' THEN 'designer' END AS k17,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(photo|تصوير|وێنە)' THEN 'photographer' END AS k18,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(video|فيديو|ڤیدیۆ)' THEN 'videographer' END AS k19,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(social|تواصل اجتماعي|سۆشيال|facebook|instagram)' THEN 'social_media' END AS k20,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(it support|دعم تقني|تكنولوج|programmer|coding)' THEN 'it_support' END AS k21,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(data entry|إدخال البيانات|datentry)' THEN 'data_entry' END AS k22,
    -- teaching/language
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(teach|معلم|مامۆستا|tutor)' THEN 'teacher' END AS k23,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(translat.*ar|arabic|ترجمة|وەرگێڕ.*عەر)' THEN 'translator_ar' END AS k24,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(translat.*en|english|إنجليزي|ئینگلیزی)' THEN 'translator_en' END AS k25,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(counsel|مرشد|ڕاوێژکار|advisor)' THEN 'counselor' END AS k26,
    -- field work
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(distribut|توزيع|دابەشکردن)' THEN 'distribution' END AS k27,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(survey|مسح|راپرسی)' THEN 'survey' END AS k28,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(logistic|لوجستيات|لۆجیستی)' THEN 'logistics' END AS k29,
    CASE WHEN lower(coalesce(va.skills,'')) ~ '(warehouse|مخزن|کۆگا)' THEN 'warehouse' END AS k30
  FROM volunteer_applications va
),
melted AS (
  -- pivot to (id, key) rows, drop nulls
  SELECT id, k AS key FROM detected, LATERAL (VALUES
    (k1),(k2),(k3),(k4),(k5),(k6),(k7),(k8),(k9),(k10),
    (k11),(k12),(k13),(k14),(k15),(k16),(k17),(k18),(k19),(k20),
    (k21),(k22),(k23),(k24),(k25),(k26),(k27),(k28),(k29),(k30)
  ) AS v(k) WHERE k IS NOT NULL
)
UPDATE volunteer_applications va
SET skill_tags = (
  SELECT array_agg(DISTINCT x ORDER BY x)
  FROM unnest(va.skill_tags || sub.new_keys) AS x
)
FROM (
  SELECT id, array_agg(DISTINCT key) AS new_keys
  FROM melted
  GROUP BY id
) sub
WHERE va.id = sub.id
  AND array_length(sub.new_keys, 1) > 0;

-- GIN index for "find volunteers with X skill" queries (admin filter).
CREATE INDEX idx_volunteer_apps_skill_tags
  ON volunteer_applications USING GIN (skill_tags);

-- ---------- 2. Per-day availability table ----------
-- One row per day-of-week the volunteer is available, with from/to times
-- in HH:MM (24h). Why a table and not JSONB? So that the admin SPA's
-- "available Wed afternoon" filter is a plain INNER JOIN, no JSON path
-- gymnastics. CASCADE on application delete keeps it tidy.
CREATE TABLE volunteer_application_availability (
  application_id BIGINT NOT NULL
    REFERENCES volunteer_applications(id) ON DELETE CASCADE,
  day_of_week    VARCHAR(3) NOT NULL
    CHECK (day_of_week IN ('mon','tue','wed','thu','fri','sat','sun')),
  time_from      VARCHAR(5) NOT NULL,  -- 'HH:MM'
  time_to        VARCHAR(5) NOT NULL,
  PRIMARY KEY (application_id, day_of_week)
);

CREATE INDEX idx_volunteer_apps_avail_day
  ON volunteer_application_availability (day_of_week);

COMMIT;
