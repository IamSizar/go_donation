-- Tracks volunteers joining open missions from the Volunteer role screen.
CREATE TABLE IF NOT EXISTS volunteer_mission_signups (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  mission_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending','approved','rejected','joined','cancelled','completed') NOT NULL DEFAULT 'pending',
  notes TEXT NULL,
  checked_in_at DATETIME NULL,
  completed_at DATETIME NULL,
  hours_served DECIMAL(8,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_volunteer_mission_signups_user_mission (user_id, mission_id),
  KEY idx_volunteer_mission_signups_user (user_id),
  KEY idx_volunteer_mission_signups_mission (mission_id),
  KEY idx_volunteer_mission_signups_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
