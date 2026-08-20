-- ============================================================
--  M5_Suspicious  |  ترقية المخطط إلى v2
--  شغّل هذا الملف مرة واحدة فقط إذا كنت قد استوردت sql.sql القديم.
--  التركيب الجديد (أول مرة) لا يحتاجه — sql.sql محدّث أصلاً.
-- ============================================================
--
--  سبب الترقية:
--  كانت المفاتيح الفريدة على (user_id, ...) بينما user_id قد يكون NULL.
--  MySQL يعتبر كل NULL قيمة مختلفة، فلا يعمل ON DUPLICATE KEY UPDATE
--  وتتراكم صفوف مكررة عند كل دخول. المفاتيح الآن على license الذي
--  يوجد دائماً لأي لاعب FiveM.
--
--  البيانات لا تُحذف. جداول الحظر (hwid_bans / license_bans) لا تتغيّر.
-- ============================================================

-- ------------------------------------------------------------
--  1. تنظيف الصفوف المكررة التي أنشأها المفتاح القديم
--     نُبقي أقدم صف لكل مفتاح جديد ونجمع فيه العدادات.
-- ------------------------------------------------------------

-- player_tokens : (license, token_hash)
CREATE TEMPORARY TABLE `m5_tok_keep` AS
    SELECT MIN(`id`) AS keep_id, `license`, `token_hash`,
           SUM(`seen_count`) AS total_seen,
           MIN(`first_seen`) AS oldest,
           MAX(`last_seen`)  AS newest
    FROM `player_tokens`
    WHERE `license` IS NOT NULL
    GROUP BY `license`, `token_hash`;

UPDATE `player_tokens` t
    JOIN `m5_tok_keep` k ON k.keep_id = t.id
    SET t.seen_count = k.total_seen,
        t.first_seen = k.oldest,
        t.last_seen  = k.newest;

DELETE t FROM `player_tokens` t
    LEFT JOIN `m5_tok_keep` k ON k.keep_id = t.id
    WHERE k.keep_id IS NULL AND t.license IS NOT NULL;

DROP TEMPORARY TABLE `m5_tok_keep`;

-- الصفوف التي لا license لها لا يمكن ربطها بأحد، احذفها.
DELETE FROM `player_tokens` WHERE `license` IS NULL;

-- player_history : (license)
CREATE TEMPORARY TABLE `m5_hist_keep` AS
    SELECT MIN(`id`) AS keep_id, `license`,
           SUM(`join_count`) AS total_joins,
           MIN(`first_seen`) AS oldest,
           MAX(`last_seen`)  AS newest
    FROM `player_history`
    WHERE `license` IS NOT NULL
    GROUP BY `license`;

UPDATE `player_history` h
    JOIN `m5_hist_keep` k ON k.keep_id = h.id
    SET h.join_count = k.total_joins,
        h.first_seen = k.oldest,
        h.last_seen  = k.newest;

DELETE h FROM `player_history` h
    LEFT JOIN `m5_hist_keep` k ON k.keep_id = h.id
    WHERE k.keep_id IS NULL AND h.license IS NOT NULL;

DROP TEMPORARY TABLE `m5_hist_keep`;

DELETE FROM `player_history` WHERE `license` IS NULL;

-- ------------------------------------------------------------
--  2. تبديل المفاتيح الفريدة
-- ------------------------------------------------------------

ALTER TABLE `player_tokens`
    DROP INDEX `uniq_user_token`,
    ADD UNIQUE KEY `uniq_license_token` (`license`, `token_hash`);

ALTER TABLE `player_history`
    DROP INDEX `uniq_user_license`,
    ADD UNIQUE KEY `uniq_license` (`license`);

-- ------------------------------------------------------------
--  3. اجعل user_id يتحمل NULL بوضوح (كان كذلك أصلاً، للتأكيد فقط)
-- ------------------------------------------------------------

ALTER TABLE `player_tokens`  MODIFY `user_id` INT UNSIGNED NULL;
ALTER TABLE `player_history` MODIFY `user_id` INT UNSIGNED NULL;

-- ------------------------------------------------------------
--  4. تنظيف أي user_id خاطئ سبق تخزينه
-- ------------------------------------------------------------

UPDATE `player_tokens`      SET `user_id` = NULL WHERE `user_id` = 0;
UPDATE `player_history`     SET `user_id` = NULL WHERE `user_id` = 0;
UPDATE `suspicious_players` SET `user_id` = NULL WHERE `user_id` = 0;
