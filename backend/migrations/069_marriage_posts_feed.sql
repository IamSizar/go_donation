-- 069 — Marriage Posts: the feed is the approved profiles themselves
-- (photo + age/city/gender + bio cards), not admin-authored blog posts.
-- Adds the one column that was missing for that: an optional profile photo,
-- uploaded by the profile owner via the generic /api/uploads endpoint
-- (same "upload, then save the path" convention used everywhere else).
ALTER TABLE marriage_profiles
  ADD COLUMN IF NOT EXISTS photo_url TEXT;
