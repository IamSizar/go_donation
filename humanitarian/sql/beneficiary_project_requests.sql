-- Maps to: lib/modules/sponsorship/screens/beneficiary_submit_project_screen.dart
-- Run the full CREATE TABLE from the first line through );

CREATE TABLE IF NOT EXISTS beneficiary_project_requests (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

  project_title VARCHAR(255) NOT NULL,
  project_title_ar VARCHAR(255) NULL,
  category VARCHAR(128) NOT NULL,
  category_ar VARCHAR(128) NULL,
  summary TEXT NOT NULL,
  summary_ar TEXT NULL,
  description_long TEXT NOT NULL,
  description_long_ar TEXT NULL,

  amount_needed DECIMAL(14,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'IQD',

  location VARCHAR(255) NOT NULL,
  location_ar VARCHAR(255) NULL,
  beneficiary_community_name VARCHAR(255) NOT NULL,
  beneficiary_community_name_ar VARCHAR(255) NULL,
  people_affected_total INT UNSIGNED NULL,

  male_count INT UNSIGNED NULL,
  female_count INT UNSIGNED NULL,
  volunteer_age_profile TEXT NULL,
  volunteer_age_profile_ar TEXT NULL,
  volunteer_skills_knowledge TEXT NULL,
  volunteer_skills_knowledge_ar TEXT NULL,
  people_volunteers_extra_description TEXT NULL,
  people_volunteers_extra_description_ar TEXT NULL,

  timeline_target VARCHAR(255) NULL,
  timeline_target_ar VARCHAR(255) NULL,

  contact_person_name VARCHAR(255) NULL,
  contact_person_name_ar VARCHAR(255) NULL,
  contact_phone VARCHAR(32) NULL,
  contact_email VARCHAR(255) NULL,
  other_notes TEXT NULL,
  other_notes_ar TEXT NULL,

  status VARCHAR(32) NOT NULL DEFAULT 'submitted',
  submitted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  submitted_by_user_id BIGINT UNSIGNED NULL,

  PRIMARY KEY (id),
  KEY idx_bpr_status (status),
  KEY idx_bpr_submitted_at (submitted_at),
  KEY idx_bpr_user (submitted_by_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
