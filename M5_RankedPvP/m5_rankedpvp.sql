-- ============================================================================
--  M5 Ranked PvP — Database Schema (MySQL / MariaDB, oxmysql)
--  The resource creates these tables automatically when
--  Config.Database.autoCreateTables = true. This file is provided for manual
--  installation and for reference.
-- ============================================================================

SET NAMES utf8mb4;

-- ----------------------------------------------------------------------------
-- Core player row
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_players` (
  `user_id`      INT UNSIGNED    NOT NULL,
  `name`         VARCHAR(64)     NOT NULL DEFAULT 'Unknown',
  `license`      VARCHAR(64)     NOT NULL DEFAULT '',
  `discord`      VARCHAR(32)     NOT NULL DEFAULT '',
  `ip_hash`      VARCHAR(64)     NOT NULL DEFAULT '',
  `level`        INT UNSIGNED    NOT NULL DEFAULT 1,
  `xp`           INT UNSIGNED    NOT NULL DEFAULT 0,
  `titles`       LONGTEXT        NULL,
  `badges`       LONGTEXT        NULL,
  `active_title` VARCHAR(48)     NOT NULL DEFAULT '',
  `frame`        VARCHAR(48)     NOT NULL DEFAULT 'default',
  `settings`     LONGTEXT        NULL,
  `commendations` INT UNSIGNED   NOT NULL DEFAULT 0,
  `reports`      INT UNSIGNED    NOT NULL DEFAULT 0,
  `playtime`     INT UNSIGNED    NOT NULL DEFAULT 0,
  `created_at`   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen`    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`),
  KEY `idx_players_license` (`license`),
  KEY `idx_players_iphash`  (`ip_hash`),
  KEY `idx_players_level`   (`level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Per season statistics
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_player_stats` (
  `user_id`         INT UNSIGNED NOT NULL,
  `season_id`       INT UNSIGNED NOT NULL,
  `matches`         INT UNSIGNED NOT NULL DEFAULT 0,
  `wins`            INT UNSIGNED NOT NULL DEFAULT 0,
  `losses`          INT UNSIGNED NOT NULL DEFAULT 0,
  `draws`           INT UNSIGNED NOT NULL DEFAULT 0,
  `kills`           INT UNSIGNED NOT NULL DEFAULT 0,
  `deaths`          INT UNSIGNED NOT NULL DEFAULT 0,
  `assists`         INT UNSIGNED NOT NULL DEFAULT 0,
  `headshots`       INT UNSIGNED NOT NULL DEFAULT 0,
  `damage`          BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `mvp`             INT UNSIGNED NOT NULL DEFAULT 0,
  `win_streak`      INT NOT NULL DEFAULT 0,
  `best_win_streak` INT NOT NULL DEFAULT 0,
  `lose_streak`     INT NOT NULL DEFAULT 0,
  `clutches`        INT UNSIGNED NOT NULL DEFAULT 0,
  `aces`            INT UNSIGNED NOT NULL DEFAULT 0,
  `first_bloods`    INT UNSIGNED NOT NULL DEFAULT 0,
  `rounds_won`      INT UNSIGNED NOT NULL DEFAULT 0,
  `rounds_played`   INT UNSIGNED NOT NULL DEFAULT 0,
  `leaves`          INT UNSIGNED NOT NULL DEFAULT 0,
  `afk_count`       INT UNSIGNED NOT NULL DEFAULT 0,
  `playtime`        INT UNSIGNED NOT NULL DEFAULT 0,
  `fav_weapon`      VARCHAR(48)  NOT NULL DEFAULT '',
  `fav_map`         VARCHAR(48)  NOT NULL DEFAULT '',
  `weapon_stats`    LONGTEXT     NULL,
  `map_stats`       LONGTEXT     NULL,
  `updated_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `season_id`),
  KEY `idx_stats_season_kills` (`season_id`, `kills`),
  KEY `idx_stats_season_wins`  (`season_id`, `wins`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Rank / RP
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_player_ranks` (
  `user_id`           INT UNSIGNED NOT NULL,
  `season_id`         INT UNSIGNED NOT NULL,
  `rp`                INT NOT NULL DEFAULT 0,
  `rank_id`           INT NOT NULL DEFAULT 0,
  `division`          INT NOT NULL DEFAULT 0,
  `highest_rank_id`   INT NOT NULL DEFAULT 0,
  `highest_rp`        INT NOT NULL DEFAULT 0,
  `placement_done`    TINYINT(1) NOT NULL DEFAULT 0,
  `placement_played`  INT NOT NULL DEFAULT 0,
  `placement_data`    LONGTEXT NULL,
  `rank_protection`   INT NOT NULL DEFAULT 0,
  `updated_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `season_id`),
  KEY `idx_ranks_board` (`season_id`, `rp` DESC),
  KEY `idx_ranks_rank`  (`season_id`, `rank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Hidden matchmaking rating
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_player_mmr` (
  `user_id`     INT UNSIGNED NOT NULL,
  `season_id`   INT UNSIGNED NOT NULL,
  `mmr`         INT NOT NULL DEFAULT 1000,
  `uncertainty` INT NOT NULL DEFAULT 350,
  `games`       INT NOT NULL DEFAULT 0,
  `peak_mmr`    INT NOT NULL DEFAULT 1000,
  `updated_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `season_id`),
  KEY `idx_mmr_season` (`season_id`, `mmr`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Matches
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_matches` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_uid`     VARCHAR(40)  NOT NULL,
  `season_id`     INT UNSIGNED NOT NULL DEFAULT 0,
  `mode`          VARCHAR(24)  NOT NULL,
  `map_id`        VARCHAR(48)  NOT NULL,
  `ranked`        TINYINT(1)   NOT NULL DEFAULT 1,
  `custom_id`     INT UNSIGNED NOT NULL DEFAULT 0,
  `state`         VARCHAR(16)  NOT NULL DEFAULT 'CLEANUP',
  `team_a_score`  INT NOT NULL DEFAULT 0,
  `team_b_score`  INT NOT NULL DEFAULT 0,
  `winner`        TINYINT NOT NULL DEFAULT 0,
  `rounds_played` INT NOT NULL DEFAULT 0,
  `overtime`      TINYINT(1) NOT NULL DEFAULT 0,
  `bucket`        INT NOT NULL DEFAULT 0,
  `avg_mmr_a`     INT NOT NULL DEFAULT 0,
  `avg_mmr_b`     INT NOT NULL DEFAULT 0,
  `balanced`      TINYINT(1) NOT NULL DEFAULT 1,
  `mvp_user_id`   INT UNSIGNED NOT NULL DEFAULT 0,
  `duration`      INT NOT NULL DEFAULT 0,
  `end_reason`    VARCHAR(32) NOT NULL DEFAULT '',
  `started_at`    DATETIME NULL,
  `ended_at`      DATETIME NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_match_uid` (`match_uid`),
  KEY `idx_matches_season` (`season_id`, `ended_at`),
  KEY `idx_matches_mode`   (`mode`),
  KEY `idx_matches_ended`  (`ended_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `m5_match_players` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_id`    INT UNSIGNED NOT NULL,
  `user_id`     INT UNSIGNED NOT NULL,
  `name`        VARCHAR(64) NOT NULL DEFAULT '',
  `team`        TINYINT NOT NULL DEFAULT 1,
  `kills`       INT NOT NULL DEFAULT 0,
  `deaths`      INT NOT NULL DEFAULT 0,
  `assists`     INT NOT NULL DEFAULT 0,
  `headshots`   INT NOT NULL DEFAULT 0,
  `damage`      INT NOT NULL DEFAULT 0,
  `score`       INT NOT NULL DEFAULT 0,
  `clutches`    INT NOT NULL DEFAULT 0,
  `first_bloods`INT NOT NULL DEFAULT 0,
  `rounds_won`  INT NOT NULL DEFAULT 0,
  `mvp`         TINYINT(1) NOT NULL DEFAULT 0,
  `rp_before`   INT NOT NULL DEFAULT 0,
  `rp_after`    INT NOT NULL DEFAULT 0,
  `rp_change`   INT NOT NULL DEFAULT 0,
  `mmr_before`  INT NOT NULL DEFAULT 0,
  `mmr_after`   INT NOT NULL DEFAULT 0,
  `rank_before` INT NOT NULL DEFAULT 0,
  `rank_after`  INT NOT NULL DEFAULT 0,
  `result`      VARCHAR(12) NOT NULL DEFAULT 'LOSS',
  `left_early`  TINYINT(1) NOT NULL DEFAULT 0,
  `afk`         TINYINT(1) NOT NULL DEFAULT 0,
  `fav_weapon`  VARCHAR(48) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_match_user` (`match_id`, `user_id`),
  KEY `idx_mp_user` (`user_id`),
  KEY `idx_mp_match` (`match_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `m5_match_rounds` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_id`   INT UNSIGNED NOT NULL,
  `round_no`   INT NOT NULL,
  `winner`     TINYINT NOT NULL DEFAULT 0,
  `duration`   INT NOT NULL DEFAULT 0,
  `reason`     VARCHAR(24) NOT NULL DEFAULT '',
  `score_a`    INT NOT NULL DEFAULT 0,
  `score_b`    INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_rounds_match` (`match_id`, `round_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `m5_match_kills` (
  `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `match_id`  INT UNSIGNED NOT NULL,
  `round_no`  INT NOT NULL DEFAULT 0,
  `killer`    INT UNSIGNED NOT NULL DEFAULT 0,
  `victim`    INT UNSIGNED NOT NULL DEFAULT 0,
  `weapon`    VARCHAR(48) NOT NULL DEFAULT '',
  `headshot`  TINYINT(1) NOT NULL DEFAULT 0,
  `distance`  FLOAT NOT NULL DEFAULT 0,
  `ts`        INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_kills_match`  (`match_id`),
  KEY `idx_kills_killer` (`killer`),
  KEY `idx_kills_victim` (`victim`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Seasons
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_seasons` (
  `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `number`    INT NOT NULL DEFAULT 1,
  `name`      VARCHAR(64) NOT NULL,
  `start_at`  DATETIME NOT NULL,
  `end_at`    DATETIME NOT NULL,
  `active`    TINYINT(1) NOT NULL DEFAULT 1,
  `rewards`   LONGTEXT NULL,
  `finalized` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_seasons_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `m5_season_players` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `season_id`      INT UNSIGNED NOT NULL,
  `user_id`        INT UNSIGNED NOT NULL,
  `name`           VARCHAR(64) NOT NULL DEFAULT '',
  `final_rp`       INT NOT NULL DEFAULT 0,
  `final_rank_id`  INT NOT NULL DEFAULT 0,
  `rank_name`      VARCHAR(32) NOT NULL DEFAULT '',
  `highest_rank_id`INT NOT NULL DEFAULT 0,
  `placement`      INT NOT NULL DEFAULT 0,
  `wins`           INT NOT NULL DEFAULT 0,
  `losses`         INT NOT NULL DEFAULT 0,
  `kd`             FLOAT NOT NULL DEFAULT 0,
  `rewarded`       TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_season_user` (`season_id`, `user_id`),
  KEY `idx_sp_board` (`season_id`, `final_rp` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Ranked bans
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_rank_bans` (
  `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`   INT UNSIGNED NOT NULL,
  `name`      VARCHAR(64) NOT NULL DEFAULT '',
  `discord`   VARCHAR(32) NOT NULL DEFAULT '',
  `license`   VARCHAR(64) NOT NULL DEFAULT '',
  `type`      VARCHAR(24) NOT NULL DEFAULT 'RANKED',
  `mode`      VARCHAR(24) NOT NULL DEFAULT '',
  `reason`    VARCHAR(255) NOT NULL DEFAULT '',
  `admin`     VARCHAR(64) NOT NULL DEFAULT 'SYSTEM',
  `admin_id`  INT UNSIGNED NOT NULL DEFAULT 0,
  `duration`  INT NOT NULL DEFAULT 0,
  `start_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expiry`    DATETIME NULL,
  `evidence`  LONGTEXT NULL,
  `notes`     LONGTEXT NULL,
  `active`    TINYINT(1) NOT NULL DEFAULT 1,
  `unbanned_by` VARCHAR(64) NOT NULL DEFAULT '',
  `unbanned_at` DATETIME NULL,
  PRIMARY KEY (`id`),
  KEY `idx_bans_user`   (`user_id`, `active`),
  KEY `idx_bans_expiry` (`expiry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Custom games
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_custom_games` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `room_uid`   VARCHAR(40) NOT NULL,
  `name`       VARCHAR(64) NOT NULL,
  `host_id`    INT UNSIGNED NOT NULL,
  `host_name`  VARCHAR(64) NOT NULL DEFAULT '',
  `mode`       VARCHAR(24) NOT NULL,
  `map_id`     VARCHAR(48) NOT NULL,
  `ranked`     TINYINT(1) NOT NULL DEFAULT 0,
  `settings`   LONGTEXT NULL,
  `players`    INT NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at`   DATETIME NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_room_uid` (`room_uid`),
  KEY `idx_custom_host` (`host_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `m5_custom_game_players` (
  `id`       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `game_id`  INT UNSIGNED NOT NULL,
  `user_id`  INT UNSIGNED NOT NULL,
  `name`     VARCHAR(64) NOT NULL DEFAULT '',
  `team`     TINYINT NOT NULL DEFAULT 1,
  `kills`    INT NOT NULL DEFAULT 0,
  `deaths`   INT NOT NULL DEFAULT 0,
  `headshots`INT NOT NULL DEFAULT 0,
  `result`   VARCHAR(12) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_cgp_game` (`game_id`),
  KEY `idx_cgp_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Anti boosting
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_anti_boost_flags` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `name`       VARCHAR(64) NOT NULL DEFAULT '',
  `target_id`  INT UNSIGNED NOT NULL DEFAULT 0,
  `type`       VARCHAR(48) NOT NULL,
  `severity`   INT NOT NULL DEFAULT 1,
  `details`    LONGTEXT NULL,
  `match_id`   INT UNSIGNED NOT NULL DEFAULT 0,
  `reviewed`   TINYINT(1) NOT NULL DEFAULT 0,
  `admin`      VARCHAR(64) NOT NULL DEFAULT '',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_flags_user`     (`user_id`, `reviewed`),
  KEY `idx_flags_severity` (`severity`),
  KEY `idx_flags_created`  (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Rewards
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_rewards` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reward_key`    VARCHAR(64) NOT NULL,
  `name`          VARCHAR(96) NOT NULL,
  `type`          VARCHAR(24) NOT NULL,
  `value`         LONGTEXT NULL,
  `rank_required` INT NOT NULL DEFAULT 0,
  `season_id`     INT UNSIGNED NOT NULL DEFAULT 0,
  `active`        TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reward_key_season` (`reward_key`, `season_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `m5_player_rewards` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `reward_key` VARCHAR(64) NOT NULL,
  `season_id`  INT UNSIGNED NOT NULL DEFAULT 0,
  `type`       VARCHAR(24) NOT NULL DEFAULT '',
  `value`      LONGTEXT NULL,
  `claimed`    TINYINT(1) NOT NULL DEFAULT 0,
  `claimed_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_player_reward` (`user_id`, `reward_key`, `season_id`),
  KEY `idx_pr_user` (`user_id`, `claimed`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Missions / achievements
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_player_missions` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `mission_key`VARCHAR(64) NOT NULL,
  `kind`       VARCHAR(12) NOT NULL DEFAULT 'daily',
  `progress`   INT NOT NULL DEFAULT 0,
  `target`     INT NOT NULL DEFAULT 1,
  `completed`  TINYINT(1) NOT NULL DEFAULT 0,
  `claimed`    TINYINT(1) NOT NULL DEFAULT 0,
  `period`     VARCHAR(16) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_mission` (`user_id`, `mission_key`, `period`),
  KEY `idx_missions_user` (`user_id`, `kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `m5_player_achievements` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`       INT UNSIGNED NOT NULL,
  `achievement`   VARCHAR(64) NOT NULL,
  `unlocked_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_achievement` (`user_id`, `achievement`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Admin audit log — every staff action, who did it, to whom and why
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_admin_logs` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `admin_id`     INT UNSIGNED NOT NULL DEFAULT 0,
  `admin_name`   VARCHAR(64) NOT NULL DEFAULT '',
  `action`       VARCHAR(48) NOT NULL,
  `target_id`    INT UNSIGNED NOT NULL DEFAULT 0,
  `target_name`  VARCHAR(64) NOT NULL DEFAULT '',
  `amount`       INT NOT NULL DEFAULT 0,
  `before_value` INT NOT NULL DEFAULT 0,
  `after_value`  INT NOT NULL DEFAULT 0,
  `reason`       VARCHAR(255) NOT NULL DEFAULT '',
  `details`      LONGTEXT NULL,
  `created_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_audit_admin`   (`admin_id`),
  KEY `idx_audit_target`  (`target_id`),
  KEY `idx_audit_action`  (`action`),
  KEY `idx_audit_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- Leave / penalty tracking
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `m5_player_penalties` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL,
  `type`       VARCHAR(24) NOT NULL DEFAULT 'LEAVE',
  `match_id`   INT UNSIGNED NOT NULL DEFAULT 0,
  `rp_lost`    INT NOT NULL DEFAULT 0,
  `cooldown`   INT NOT NULL DEFAULT 0,
  `expires_at` DATETIME NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pen_user` (`user_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
