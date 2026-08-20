-- ============================================================
--  m5_suspicious - database schema
--  MySQL 5.7+ / MariaDB 10.2+
-- ============================================================

-- ------------------------------------------------------------
--  Every token we have ever seen, hashed. Raw tokens are never stored.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `player_tokens` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`     INT UNSIGNED NULL,
    `license`     VARCHAR(80)  NULL,
    `token_hash`  CHAR(64)     NOT NULL,
    `token_mask`  VARCHAR(48)  NOT NULL,
    `first_seen`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `seen_count`  INT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    -- المفتاح على license وليس user_id: الـ user_id قد يكون NULL (لاعب جديد
    -- أو جدول vRP مختلف)، و MySQL يعتبر كل NULL قيمة مختلفة، فلا يعمل
    -- ON DUPLICATE KEY وتتراكم صفوف مكررة عند كل دخول.
    UNIQUE KEY `uniq_license_token` (`license`, `token_hash`),
    KEY `idx_token_hash` (`token_hash`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_license` (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Connection history - powers "shared IP", "first join", "new account"
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `player_history` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`      INT UNSIGNED NULL,
    `player_name`  VARCHAR(96)  NULL,
    `license`      VARCHAR(80)  NULL,
    `ip`           VARCHAR(64)  NULL,
    `discord`      VARCHAR(64)  NULL,
    `steam`        VARCHAR(64)  NULL,
    `fivem`        VARCHAR(64)  NULL,
    `country`      VARCHAR(64)  NULL,
    `region`       VARCHAR(64)  NULL,
    `city`         VARCHAR(64)  NULL,
    `token_count`  TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `first_seen`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `join_count`   INT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_license` (`license`),
    KEY `idx_ip` (`ip`),
    KEY `idx_license` (`license`),
    KEY `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Detections
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `suspicious_players` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`      INT UNSIGNED NULL,
    `player_name`  VARCHAR(96)  NULL,
    `server_id`    SMALLINT UNSIGNED NULL,
    `license`      VARCHAR(80)  NULL,
    `ip`           VARCHAR(64)  NULL,
    `discord`      VARCHAR(64)  NULL,
    `steam`        VARCHAR(64)  NULL,
    `fivem`        VARCHAR(64)  NULL,
    `risk_score`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `risk_level`   VARCHAR(16)  NOT NULL DEFAULT 'LOW',
    `reasons`      TEXT         NULL,           -- JSON array of reason keys
    `vpn`          TINYINT      NOT NULL DEFAULT -1,  -- -1 unknown, 0 no, 1 yes
    `new_account`  TINYINT(1)   NOT NULL DEFAULT 0,
    `shared_ip`    INT UNSIGNED NOT NULL DEFAULT 0,
    `shared_hwid`  INT UNSIGNED NOT NULL DEFAULT 0,
    `token_count`  TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `country`      VARCHAR(64)  NULL,
    `region`       VARCHAR(64)  NULL,
    `city`         VARCHAR(64)  NULL,
    `status`       ENUM('pending','ignored','actioned') NOT NULL DEFAULT 'pending',
    `handled_by`   VARCHAR(96)  NULL,
    `handled_at`   DATETIME     NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_status_created` (`status`, `created_at`),
    KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  HWID bans - one row per banned token
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `hwid_bans` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `token`       CHAR(64)     NOT NULL,   -- salted SHA-256 of the raw token
    `token_mask`  VARCHAR(48)  NOT NULL,   -- display only, e.g. 8ca357ca...2b686b
    `user_id`     INT UNSIGNED NULL,
    `player_name` VARCHAR(96)  NULL,
    `reason`      VARCHAR(255) NOT NULL DEFAULT '',
    `banned_by`   VARCHAR(96)  NOT NULL DEFAULT 'console',
    `banned_by_id` INT UNSIGNED NULL,
    `group_id`    VARCHAR(40)  NULL,       -- links tokens banned in one action
    `active`      TINYINT(1)   NOT NULL DEFAULT 1,
    `unbanned_by` VARCHAR(96)  NULL,
    `unbanned_at` DATETIME     NULL,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at`  DATETIME     NULL,       -- NULL = permanent
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_token` (`token`),
    KEY `idx_active` (`active`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_group` (`group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  License bans (identifier bans) - used by [Ban License] / [Ban Player]
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `license_bans` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `license`     VARCHAR(80)  NOT NULL,
    `user_id`     INT UNSIGNED NULL,
    `player_name` VARCHAR(96)  NULL,
    `reason`      VARCHAR(255) NOT NULL DEFAULT '',
    `banned_by`   VARCHAR(96)  NOT NULL DEFAULT 'console',
    `banned_by_id` INT UNSIGNED NULL,
    `active`      TINYINT(1)   NOT NULL DEFAULT 1,
    `unbanned_by` VARCHAR(96)  NULL,
    `unbanned_at` DATETIME     NULL,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at`  DATETIME     NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_license` (`license`),
    KEY `idx_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Audit trail for every administrative action
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `suspicious_actions` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `action`      VARCHAR(32)  NOT NULL,   -- ban_hwid / ban_license / ban_player / ignore / unban / detected
    `target_user` INT UNSIGNED NULL,
    `target_name` VARCHAR(96)  NULL,
    `admin_user`  INT UNSIGNED NULL,
    `admin_name`  VARCHAR(96)  NULL,
    `details`     TEXT         NULL,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_target_user` (`target_user`),
    KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
--  Cached VPN / geo lookups so the API is hit once per IP
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `ip_intel_cache` (
    `ip`         VARCHAR(64) NOT NULL,
    `vpn`        TINYINT     NOT NULL DEFAULT -1,
    `country`    VARCHAR(64) NULL,
    `region`     VARCHAR(64) NULL,
    `city`       VARCHAR(64) NULL,
    `isp`        VARCHAR(96) NULL,
    `checked_at` DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`ip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
