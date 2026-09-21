-- ============================================================================
--  M5 Ranked PvP — ten made-up players, so the world board has something on it
-- ============================================================================
--  A brand new server has no matches, so the ladder is empty and the board out
--  in the world looks broken. This fills it with ten invented players spread
--  across the ranks — Radiant down to Silver — so you can stand in front of it,
--  see the podium, the medals, the K/D columns and the rank colours, and place
--  the panel properly before anybody has played.
--
--  These are NOT real accounts. Nothing can log in as them, they will never be
--  matched against anyone, and they take no slot. They exist only in the three
--  tables the board reads.
--
--  ⚠ THEY ARE FOR TESTING. Take them off before the server opens — the cleanup
--    is the last block in this file and it is one statement.
--
--  For putting a REAL player on the board, use m5_rankedpvp_board_seed.sql
--  instead; that one is written to be run per player with their own user id.
--
--  After running it, in the SERVER CONSOLE:
--
--      m5boardrefresh
--
--  which rebuilds the board, pushes it to everyone and prints the top ten.
--  Without it you wait for Config.WorldBoard.refresh (five minutes by default).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- The season and the ladder the board shows.
-- ----------------------------------------------------------------------------
-- The mode is Config.RankPools.default in Config_Server.lua — '1v1' unless you
-- changed it, and it must match Config.WorldBoard.mode if you set that.
SET @season = (SELECT `id` FROM `m5_seasons` WHERE `active` = 1 ORDER BY `id` DESC LIMIT 1);
SET @mode   = '1v1';

-- Run this line on its own first. If it says NO ACTIVE SEASON, start the
-- resource once (it creates the season) and come back.
SELECT IF(@season IS NULL,
          'NO ACTIVE SEASON — start the resource once, then run this file again',
          CONCAT('ok: season ', @season, ', mode ', @mode)) AS `check_this_first`;

-- ----------------------------------------------------------------------------
-- 1. The players themselves
-- ----------------------------------------------------------------------------
-- user_id 900001-900010 is deliberately far out of the way of real vRP ids, so
-- nothing of yours can be overwritten and the cleanup at the bottom can find
-- them again with one WHERE.
--
-- ped_model is who stands on the podium. The top three are spawned wearing it.
-- Leave a 0 there and the podium falls back to Config.WorldBoard.podium.fallback.
--
-- The name is what shows on the board. It is measured and shrunk to fit, so a
-- long one is safe.
INSERT INTO `m5_players` (`user_id`, `name`, `level`, `ped_model`) VALUES
  (900001, 'SHADOW',    92, 3250873975),  -- a_m_y_skater_01
  (900002, 'VIPER',     88,  587703123),  -- a_m_y_hipster_01
  (900003, 'GHOST',     81, 2120901815),  -- a_m_m_business_01
  (900004, 'FALCON',    74, 2549481101),  -- a_f_y_hipster_02
  (900005, 'REAPER',    69, 3523131524),  -- a_m_y_beach_01
  (900006, 'STORM',     61, 3482496489),  -- a_m_y_stbla_01
  (900007, 'BLAZE',     54, 3609190705),  -- a_m_y_golfer_01
  (900008, 'FROST',     47, 3365863812),  -- a_m_m_tourist_01
  (900009, 'ECHO',      38, 1165780219),  -- a_f_y_fitness_01
  (900010, 'NOVA',      29, 1264851357)   -- a_m_y_vinewood_01
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`), `level` = VALUES(`level`),
  `ped_model` = VALUES(`ped_model`);

-- ----------------------------------------------------------------------------
-- 2. Where they sit on the ladder
-- ----------------------------------------------------------------------------
-- The board sorts on rp, and the rank badge and its colour come from rank_id.
-- The CASE below turns rp into the right rank_id and division from the default
-- Config.Ranks, so the badges are correct without touching the admin panel.
--
-- ⚠ If you edited Config.Ranks (changed rpRequired, added a tier), these
--   numbers no longer match it. Either fix the CASE, or leave it and then run
--   Admin → Points → Set RP on each id, which recalculates from your config.
--
-- placement_done = 1 matters when Config.WorldBoard.requirePlacement is true;
-- without it they are held off the board until they finish placements.
INSERT INTO `m5_player_ranks`
       (`user_id`, `season_id`, `mode`, `rp`, `highest_rp`,
        `rank_id`, `division`, `highest_rank_id`,
        `placement_done`, `placement_played`)
SELECT  f.`user_id`, @season, @mode, f.`rp`, f.`rp`,
        CASE WHEN f.`rp` >= 2600 THEN 23 WHEN f.`rp` >= 2260 THEN 22
             WHEN f.`rp` >= 2120 THEN 21 WHEN f.`rp` >= 1990 THEN 20
             WHEN f.`rp` >= 1860 THEN 19 WHEN f.`rp` >= 1740 THEN 18
             WHEN f.`rp` >= 1620 THEN 17 WHEN f.`rp` >= 1500 THEN 16
             WHEN f.`rp` >= 1400 THEN 15 WHEN f.`rp` >= 1300 THEN 14
             WHEN f.`rp` >= 1200 THEN 13 WHEN f.`rp` >= 1100 THEN 12
             WHEN f.`rp` >= 1000 THEN 11 WHEN f.`rp` >=  900 THEN 10
             WHEN f.`rp` >=  800 THEN  9 WHEN f.`rp` >=  700 THEN  8
             WHEN f.`rp` >=  600 THEN  7 WHEN f.`rp` >=  500 THEN  6
             WHEN f.`rp` >=  400 THEN  5 WHEN f.`rp` >=  300 THEN  4
             WHEN f.`rp` >=  200 THEN  3 WHEN f.`rp` >=  100 THEN  2
             ELSE 1 END,
        CASE WHEN f.`rp` >= 2260 THEN 0
             WHEN f.`rp` >= 2120 THEN 3 WHEN f.`rp` >= 1990 THEN 2
             WHEN f.`rp` >= 1860 THEN 1 WHEN f.`rp` >= 1740 THEN 3
             WHEN f.`rp` >= 1620 THEN 2 WHEN f.`rp` >= 1500 THEN 1
             WHEN f.`rp` >= 1400 THEN 3 WHEN f.`rp` >= 1300 THEN 2
             WHEN f.`rp` >= 1200 THEN 1 WHEN f.`rp` >= 1100 THEN 3
             WHEN f.`rp` >= 1000 THEN 2 WHEN f.`rp` >=  900 THEN 1
             WHEN f.`rp` >=  800 THEN 3 WHEN f.`rp` >=  700 THEN 2
             WHEN f.`rp` >=  600 THEN 1 WHEN f.`rp` >=  500 THEN 3
             WHEN f.`rp` >=  400 THEN 2 WHEN f.`rp` >=  300 THEN 1
             WHEN f.`rp` >=  200 THEN 3 WHEN f.`rp` >=  100 THEN 2
             ELSE 1 END,
        CASE WHEN f.`rp` >= 2600 THEN 23 WHEN f.`rp` >= 2260 THEN 22
             WHEN f.`rp` >= 2120 THEN 21 WHEN f.`rp` >= 1990 THEN 20
             WHEN f.`rp` >= 1860 THEN 19 WHEN f.`rp` >= 1740 THEN 18
             WHEN f.`rp` >= 1620 THEN 17 WHEN f.`rp` >= 1500 THEN 16
             WHEN f.`rp` >= 1400 THEN 15 WHEN f.`rp` >= 1300 THEN 14
             WHEN f.`rp` >= 1200 THEN 13 WHEN f.`rp` >= 1100 THEN 12
             WHEN f.`rp` >= 1000 THEN 11 WHEN f.`rp` >=  900 THEN 10
             WHEN f.`rp` >=  800 THEN  9 WHEN f.`rp` >=  700 THEN  8
             WHEN f.`rp` >=  600 THEN  7 WHEN f.`rp` >=  500 THEN  6
             WHEN f.`rp` >=  400 THEN  5 WHEN f.`rp` >=  300 THEN  4
             WHEN f.`rp` >=  200 THEN  3 WHEN f.`rp` >=  100 THEN  2
             ELSE 1 END,
        1, 0
FROM (
  -- the ranks these land on: Radiant, Immortal, Ascendant III, Ascendant I,
  -- Diamond II, Diamond I, Platinum II, Gold III, Gold I, Silver III
            SELECT 900001 AS `user_id`, 2680 AS `rp`
  UNION ALL SELECT 900002, 2310
  UNION ALL SELECT 900003, 2140
  UNION ALL SELECT 900004, 1880
  UNION ALL SELECT 900005, 1650
  UNION ALL SELECT 900006, 1520
  UNION ALL SELECT 900007, 1340
  UNION ALL SELECT 900008, 1180
  UNION ALL SELECT 900009,  960
  UNION ALL SELECT 900010,  820
) AS f
-- nothing is written at all if there is no active season, rather than ten rows
-- landing on season 0 where the board will never look for them
WHERE @season IS NOT NULL
ON DUPLICATE KEY UPDATE
  `rp` = VALUES(`rp`),
  `highest_rp` = GREATEST(`highest_rp`, VALUES(`rp`)),
  `rank_id` = VALUES(`rank_id`),
  `division` = VALUES(`division`),
  `highest_rank_id` = GREATEST(`highest_rank_id`, VALUES(`rank_id`)),
  `placement_done` = 1;

-- ----------------------------------------------------------------------------
-- 3. The numbers in the columns
-- ----------------------------------------------------------------------------
-- W / L / K / D, and the board works the K/D ratio out from the last two.
INSERT INTO `m5_player_stats`
       (`user_id`, `season_id`, `matches`, `wins`, `losses`,
        `kills`, `deaths`, `assists`, `headshots`, `mvp`, `best_win_streak`)
VALUES
  (900001, @season, 412, 301, 111, 2184,  946, 122, 741, 96, 19),
  (900002, @season, 387, 268, 119, 1903,  980, 104, 612, 81, 14),
  (900003, @season, 351, 236, 115, 1742,  935,  97, 548, 72, 12),
  (900004, @season, 298, 190, 108, 1455,  889,  88, 431, 55, 11),
  (900005, @season, 264, 160, 104, 1268,  846,  73, 366, 44,  9),
  (900006, @season, 233, 136,  97, 1094,  792,  66, 302, 37,  8),
  (900007, @season, 201, 111,  90,  921,  735,  59, 244, 28,  7),
  (900008, @season, 176,  92,  84,  788,  690,  48, 197, 21,  6),
  (900009, @season, 142,  70,  72,  611,  604,  39, 142, 15,  5),
  (900010, @season, 118,  55,  63,  482,  551,  31, 108, 11,  4)
ON DUPLICATE KEY UPDATE
  `matches` = VALUES(`matches`), `wins` = VALUES(`wins`),
  `losses`  = VALUES(`losses`),  `kills` = VALUES(`kills`),
  `deaths`  = VALUES(`deaths`),  `assists` = VALUES(`assists`),
  `headshots` = VALUES(`headshots`), `mvp` = VALUES(`mvp`),
  `best_win_streak` = VALUES(`best_win_streak`);

-- ----------------------------------------------------------------------------
-- 4. See what the board is about to show
-- ----------------------------------------------------------------------------
-- This is the same join and the same order the resource uses, so these ten
-- rows in this order are what ends up on the panel.
SELECT r.`user_id`, p.`name`, r.`rp`, r.`rank_id`, r.`division`,
       s.`wins`, s.`losses`, s.`kills`, s.`deaths`,
       ROUND(s.`kills` / NULLIF(s.`deaths`, 0), 2) AS `kd`
FROM   `m5_player_ranks` r
LEFT JOIN `m5_players`      p ON p.`user_id` = r.`user_id`
LEFT JOIN `m5_player_stats` s ON s.`user_id` = r.`user_id` AND s.`season_id` = r.`season_id`
WHERE  r.`season_id` = @season AND r.`mode` = @mode
ORDER BY r.`rp` DESC, s.`wins` DESC
LIMIT 25;

-- ============================================================================
--  TAKING THEM OFF AGAIN
-- ============================================================================
--  Run these three lines when you are done testing. They only touch the ten
--  invented ids, so nothing real is at risk. Then run m5boardrefresh again.
--
--  DELETE FROM `m5_player_ranks` WHERE `user_id` BETWEEN 900001 AND 900010;
--  DELETE FROM `m5_player_stats` WHERE `user_id` BETWEEN 900001 AND 900010;
--  DELETE FROM `m5_players`      WHERE `user_id` BETWEEN 900001 AND 900010;
-- ============================================================================
