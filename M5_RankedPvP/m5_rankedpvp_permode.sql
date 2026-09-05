-- ---------------------------------------------------------------------------
-- M5 Ranked PvP — upgrade to per-mode ranks
-- ---------------------------------------------------------------------------
-- Only for a database created BEFORE per-mode ranks. A fresh install from
-- m5_rankedpvp.sql already has these columns and needs none of this.
--
-- The resource also runs this migration itself on start when
-- Config.Database.autoCreateTables is on, so most servers never need this
-- file. It is here for anyone who prefers to migrate by hand.
--
-- WHAT IT DOES
--   Adds a `mode` column naming the ladder each row belongs to, stamps every
--   existing row with '1v1', and widens the primary key so one player can hold
--   a separate rank in every mode.
--
-- BEFORE YOU RUN IT
--   * Take a backup.
--   * '1v1' below must match Config.RankPools.legacy. If you changed that,
--     change it in all four places here too, or existing ranks land on a
--     ladder nobody plays and everyone appears Unranked.
--   * Stop the resource first, so nothing writes while the key is being
--     rebuilt.
-- ---------------------------------------------------------------------------

ALTER TABLE `m5_player_ranks`
  ADD COLUMN `mode` VARCHAR(24) NOT NULL DEFAULT '1v1' AFTER `season_id`;
UPDATE `m5_player_ranks` SET `mode` = '1v1' WHERE `mode` = '';
ALTER TABLE `m5_player_ranks`
  DROP PRIMARY KEY,
  ADD PRIMARY KEY (`user_id`, `season_id`, `mode`);

ALTER TABLE `m5_player_mmr`
  ADD COLUMN `mode` VARCHAR(24) NOT NULL DEFAULT '1v1' AFTER `season_id`;
UPDATE `m5_player_mmr` SET `mode` = '1v1' WHERE `mode` = '';
ALTER TABLE `m5_player_mmr`
  DROP PRIMARY KEY,
  ADD PRIMARY KEY (`user_id`, `season_id`, `mode`);

-- Old indexes still work, but these match how the boards now query.
ALTER TABLE `m5_player_ranks`
  DROP INDEX `idx_ranks_board`,
  ADD  INDEX `idx_ranks_board` (`season_id`, `mode`, `rp`);
ALTER TABLE `m5_player_mmr`
  DROP INDEX `idx_mmr_season`,
  ADD  INDEX `idx_mmr_season` (`season_id`, `mode`, `mmr`);
