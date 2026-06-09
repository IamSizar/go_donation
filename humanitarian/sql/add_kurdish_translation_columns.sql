ALTER TABLE `beneficiary_project_requests`
  ADD COLUMN IF NOT EXISTS `project_title_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `project_title_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `category_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `category_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `summary_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `summary_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_long_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_long_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `location_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `location_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `beneficiary_community_name_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `beneficiary_community_name_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `volunteer_age_profile_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `volunteer_age_profile_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `volunteer_skills_knowledge_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `volunteer_skills_knowledge_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `people_volunteers_extra_description_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `people_volunteers_extra_description_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `timeline_target_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `timeline_target_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `contact_person_name_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `contact_person_name_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `other_notes_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `other_notes_badini` TEXT NULL;

ALTER TABLE `beneficiary_cases`
  ADD COLUMN IF NOT EXISTS `public_title_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `public_title_badini` TEXT NULL;

ALTER TABLE `marketplace_products`
  ADD COLUMN IF NOT EXISTS `name_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `name_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_badini` TEXT NULL;

ALTER TABLE `city_directory_entries`
  ADD COLUMN IF NOT EXISTS `name_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `name_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_badini` TEXT NULL;

ALTER TABLE `partners`
  ADD COLUMN IF NOT EXISTS `name_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `name_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_badini` TEXT NULL;

ALTER TABLE `media_posts`
  ADD COLUMN IF NOT EXISTS `title_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `title_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `body_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `body_badini` TEXT NULL;

ALTER TABLE `volunteer_missions`
  ADD COLUMN IF NOT EXISTS `title_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `title_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_badini` TEXT NULL;

ALTER TABLE `app_notifications`
  ADD COLUMN IF NOT EXISTS `title_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `title_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `body_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `body_badini` TEXT NULL;

ALTER TABLE `campaigns`
  ADD COLUMN IF NOT EXISTS `title_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `title_badini` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_sorani` TEXT NULL,
  ADD COLUMN IF NOT EXISTS `description_badini` TEXT NULL;
