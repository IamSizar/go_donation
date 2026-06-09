-- Add bilingual Arabic columns to an existing `beneficiary_project_requests` table.
-- All are optional (NULL allowed). Run once on MySQL/MariaDB 5.7+.

ALTER TABLE beneficiary_project_requests
  ADD COLUMN project_title_ar VARCHAR(255) NULL AFTER project_title,
  ADD COLUMN category_ar VARCHAR(128) NULL AFTER category,
  ADD COLUMN summary_ar TEXT NULL AFTER summary,
  ADD COLUMN description_long_ar TEXT NULL AFTER description_long,
  ADD COLUMN location_ar VARCHAR(255) NULL AFTER location,
  ADD COLUMN beneficiary_community_name_ar VARCHAR(255) NULL AFTER beneficiary_community_name,
  ADD COLUMN volunteer_age_profile_ar TEXT NULL AFTER volunteer_age_profile,
  ADD COLUMN volunteer_skills_knowledge_ar TEXT NULL AFTER volunteer_skills_knowledge,
  ADD COLUMN people_volunteers_extra_description_ar TEXT NULL AFTER people_volunteers_extra_description,
  ADD COLUMN timeline_target_ar VARCHAR(255) NULL AFTER timeline_target,
  ADD COLUMN contact_person_name_ar VARCHAR(255) NULL AFTER contact_person_name,
  ADD COLUMN other_notes_ar TEXT NULL AFTER other_notes;
