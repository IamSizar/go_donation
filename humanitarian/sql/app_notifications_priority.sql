-- Adds notification tags/categories and priority sorting support.
-- Safe to run more than once.

SET @has_notification_category := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'app_notifications'
    AND COLUMN_NAME = 'notification_category'
);
SET @sql := IF(
  @has_notification_category = 0,
  "ALTER TABLE app_notifications ADD COLUMN notification_category VARCHAR(32) NOT NULL DEFAULT 'normal' AFTER notification_type",
  "SELECT 'notification_category already exists'"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_action_url := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'app_notifications'
    AND COLUMN_NAME = 'action_url'
);
SET @sql := IF(
  @has_action_url = 0,
  "ALTER TABLE app_notifications ADD COLUMN action_url VARCHAR(255) NULL DEFAULT NULL AFTER priority",
  "SELECT 'action_url already exists'"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_related_entity_type := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'app_notifications'
    AND COLUMN_NAME = 'related_entity_type'
);
SET @sql := IF(
  @has_related_entity_type = 0,
  "ALTER TABLE app_notifications ADD COLUMN related_entity_type VARCHAR(64) NULL DEFAULT NULL AFTER action_url",
  "SELECT 'related_entity_type already exists'"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_related_entity_id := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'app_notifications'
    AND COLUMN_NAME = 'related_entity_id'
);
SET @sql := IF(
  @has_related_entity_id = 0,
  "ALTER TABLE app_notifications ADD COLUMN related_entity_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER related_entity_type",
  "SELECT 'related_entity_id already exists'"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_priority := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'app_notifications'
    AND COLUMN_NAME = 'priority'
);
SET @sql := IF(
  @has_priority = 0,
  "ALTER TABLE app_notifications ADD COLUMN priority INT NOT NULL DEFAULT 0 AFTER notification_category",
  "SELECT 'priority already exists'"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS `app_notification_reads` (
  `notification_id` bigint UNSIGNED NOT NULL,
  `user_id` int UNSIGNED NOT NULL,
  `read_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`notification_id`, `user_id`),
  KEY `idx_app_notification_reads_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @has_read_at := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'app_notifications'
    AND COLUMN_NAME = 'read_at'
);
SET @sql := IF(
  @has_read_at = 0,
  "ALTER TABLE app_notifications ADD COLUMN read_at TIMESTAMP NULL DEFAULT NULL AFTER is_read",
  "SELECT 'read_at already exists'"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_priority_index := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'app_notifications'
    AND INDEX_NAME = 'idx_app_notifications_priority'
);
SET @sql := IF(
  @has_priority_index = 0,
  "ALTER TABLE app_notifications ADD INDEX idx_app_notifications_priority (is_read, notification_category, priority, created_at)",
  "SELECT 'idx_app_notifications_priority already exists'"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
