-- ============================================================================
--  M5 Ranked PvP — putting a player on the world leaderboard by hand
-- ============================================================================
--  The board reads the ladder, and the ladder is built from real matches. On a
--  new server nobody has played one yet, so the board is empty and looks
--  broken. This puts a player on it directly.
--
--  Run it once per player. Change the three values in the SET block at the top
--  and nothing else.
--
--  It is safe to run twice on the same player: every write is an upsert, so
--  the second run updates rather than duplicating.
--
--  ⚠ It does NOT invent a rank badge. Leave the resource to do that: after the
--    rows exist, open the admin panel → POINTS → **Set RP** on the same id (any
--    value, even the one you used here). That recalculates the rank, the
--    division and the placement state properly from Config.Ranks.
--
--  The board rebuilds itself on Config.WorldBoard.refresh (five minutes by
--  default). To see it straight away, run this in the SERVER CONSOLE:
--
--      m5boardrefresh
--
--  which rebuilds it, pushes it to everyone, and prints the top ten so you can
--  check the rows landed where you expected.
-- ============================================================================

SET @user_id = 1;                 -- the vRP user id
SET @name    = 'PLAYER NAME';     -- what shows on the board
SET @rp      = 1500;              -- ranked points; the board sorts on this

-- Wins, losses and so on are what the board's columns read. Leave the zeros
-- if you only care about the order and the score.
SET @wins    = 0;
SET @losses  = 0;
SET @kills   = 0;
SET @deaths  = 0;
SET @level   = 1;

-- ----------------------------------------------------------------------------
-- Nothing below here needs changing.
-- ----------------------------------------------------------------------------

-- The active season and the ladder the board is configured to show. The mode
-- is Config.RankPools.default in Config_Server.lua — '1v1' unless you changed
-- it, and it must match Config.WorldBoard.mode if you set that.
SET @season = (SELECT `id` FROM `m5_seasons` WHERE `active` = 1 ORDER BY `id` DESC LIMIT 1);
SET @mode   = '1v1';

-- The player row: the board takes the name, the level and the podium ped from
-- here. A player who has joined the server already has one; this fills in a
-- player who has not.
INSERT INTO `m5_players` (`user_id`, `name`, `level`)
VALUES (@user_id, @name, @level)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `level` = VALUES(`level`);

-- The ladder row: this is what the board sorts and what puts them on it.
-- placement_done = 1 matters when Config.WorldBoard.requirePlacement is true —
-- without it they are held back until they finish their placement matches.
INSERT INTO `m5_player_ranks`
       (`user_id`, `season_id`, `mode`, `rp`, `highest_rp`, `placement_done`, `placement_played`)
VALUES (@user_id, @season, @mode, @rp, @rp, 1, 0)
ON DUPLICATE KEY UPDATE
       `rp` = VALUES(`rp`),
       `highest_rp` = GREATEST(`highest_rp`, VALUES(`rp`)),
       `placement_done` = 1;

-- The stats row: the board's W / L / K / D / KD columns.
INSERT INTO `m5_player_stats`
       (`user_id`, `season_id`, `matches`, `wins`, `losses`, `kills`, `deaths`)
VALUES (@user_id, @season, @wins + @losses, @wins, @losses, @kills, @deaths)
ON DUPLICATE KEY UPDATE
       `matches` = VALUES(`matches`), `wins` = VALUES(`wins`),
       `losses` = VALUES(`losses`), `kills` = VALUES(`kills`),
       `deaths` = VALUES(`deaths`);

-- Check it landed, and see where they sit:
SELECT r.`user_id`, p.`name`, r.`rp`, r.`rank_id`, r.`placement_done`,
       s.`wins`, s.`losses`, s.`kills`, s.`deaths`
FROM   `m5_player_ranks` r
LEFT JOIN `m5_players`      p ON p.`user_id` = r.`user_id`
LEFT JOIN `m5_player_stats` s ON s.`user_id` = r.`user_id` AND s.`season_id` = r.`season_id`
WHERE  r.`season_id` = @season AND r.`mode` = @mode
ORDER BY r.`rp` DESC
LIMIT 25;
