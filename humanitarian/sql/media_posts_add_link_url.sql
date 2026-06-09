ALTER TABLE `media_posts`
  ADD COLUMN `link_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `media_url`;
