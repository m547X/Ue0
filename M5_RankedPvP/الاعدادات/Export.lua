--[[
    ============================================================================
     M5 Ranked PvP — Export.lua
    ----------------------------------------------------------------------------
     هذا ملفك أنت. حط فيه أي شي تبيه يصير حول القيم.

     ما تحتاج تعدّل أي ملف ثاني في السكربت عشان تضيف شغلك: اكتب جوّه أي hook
     وينفّذ بتلك اللحظة. كل hook ينستدعى داخل pcall، فالغلط هنا يطبع رسالة
     خطأ والقيم تكمل عادي — مستحيل يكسر نظام الـ PvP.

     الملف هذا shared_script: نفس الملف ينحمّل بالكلنت وبالسيرفر. الـ M5.Client
     تشتغل بالكلنت فقط والـ M5.Server تشتغل بالسيرفر فقط، فدايماً واضح كودك
     على أي جهة. نيتف الكلنت مكانها M5.Client، وقاعدة البيانات و vRP مكانهم
     M5.Server.

     ثلاث طرق تتفاعل بها مع السكربت، استخدم الي يناسبك:

       ١. اكتب جوّه hook تحت.                        (أسهل شي)
       ٢. استمع للأحداث الي يطلقها:                  (من سكربت ثاني)
              AddEventHandler('m5rp:onMatchJoin', function(data) end)
          أحداث الكلنت تطلق بالكلنت، وأحداث السيرفر بالسيرفر.
       ٣. نادِ الـ exports الي يسجّلها:              (من سكربت ثاني)
              exports.M5_RankedPvP:isInMatch()
              exports.M5_RankedPvP:getMatchInfo()
              exports.M5_RankedPvP:getPlayerRank(userId)   -- بالسيرفر فقط

     الأسماء تحت ثابتة؛ ممكن تنضاف hooks جديدة، لكن الموجودة ما يتغير شكلها.
    ============================================================================
]]

M5 = M5 or {}

-- ============================================================================
-- هوكات الكلنت
-- ============================================================================
-- تشتغل على جهاز اللاعب نفسه. استخدم نيتف الكلنت هنا.

M5.Client = {

    --- اللاعب دخل قيم للتو، قبل ما يبدأ أول راوند.
    --- data = {
    ---   matchId, mode, modeLabel, ranked (bool), custom (bool),
    ---   practice (bool، true لقيم البوتات)، team (1 أو 2)، ffa (bool)،
    ---   map = { id, name }، players (رقم)
    --- }
    onMatchJoin = function(data)
        -- مثال: خفِّ هود ثاني طول ما القتال شغّال
        -- TriggerEvent('esx_status:pause', true)
        -- exports['my_hud']:setVisible(false)
    end,

    --- اللاعب خرج من القيم — خلّصها، أو انسحب، أو انطرد.
    --- data = { matchId, reason = 'END' | 'LEAVE' | 'KICK' | 'DISCONNECT' }
    onMatchLeave = function(data)
        -- مثال: رجّع الهود حقك
        -- TriggerEvent('esx_status:pause', false)
        -- exports['my_hud']:setVisible(true)
    end,

    --- الراوند صار live (العد التنازلي خلص).
    --- data = { matchId, round, time }
    onRoundStart = function(data)
    end,

    --- الراوند انتهى.
    --- data = { matchId, round, winner (1 أو 2 أو 0)، reason، scores = { a, b } }
    onRoundEnd = function(data)
    end,

    --- هذا اللاعب مات داخل قيم.
    --- data = { matchId, killer, weapon, headshot (bool), respawn (bool) }
    onDeath = function(data)
    end,

    --- القيم كلها انتهت وشاشة النتيجة انفتحت.
    --- data = { matchId, result = 'WIN' | 'LOSS' | 'DRAW'، scores، rp = { delta } }
    onMatchEnd = function(data)
    end,

    --- دخل أو خرج من ساحة التدريب.
    --- data = { kind, label }
    onTrainingStart = function(data)
    end,
    onTrainingEnd = function(data)
    end
}

-- ============================================================================
-- هوكات السيرفر
-- ============================================================================
-- تشتغل على السيرفر. استخدم oxmysql و vRP وأي شي سيرفر سايد هنا.

M5.Server = {

    --- لاعب دخل قيم. تنستدعى مرة لكل لاعب.
    --- data = {
    ---   userId, source, name, matchId, mode, ranked (bool), custom (bool),
    ---   practice (bool), team, rankId, rank, rp, mmr
    --- }
    onMatchJoin = function(data)
        -- مثال: اخصم رسوم دخول، أو اكتب لوق خاص فيك
        -- vRP.tryPayment({ data.userId, 500 })
        -- print(('%s entered match %s'):format(data.name, data.matchId))
    end,

    --- لاعب خرج من قيم، لأي سبب كان.
    --- data = { userId, source, name, matchId, reason }
    onMatchLeave = function(data)
        -- print(('%s left match %s (%s)'):format(data.name, data.matchId, data.reason))
    end,

    --- القيم خلصت وكل الجوائز انصرفت من السكربت قبل هذي اللحظة.
    --- data = {
    ---   matchId, mode, ranked, winner (1 أو 2 أو 0)، scores = { a, b },
    ---   mvp = userId أو nil،
    ---   players = { { userId, name, team, kills, deaths, assists, headshots,
    ---                 damage, score, won (bool), rpDelta } , ... }
    --- }
    onMatchEnd = function(data)
        -- مثال: اعطِ الفايزين شي من عندك
        -- for _, p in ipairs(data.players) do
        --     if p.won then vRP.giveMoney({ p.userId, 5000 }) end
        -- end
    end,

    --- قتلة وحدة، زي ما حسمها السيرفر. موثوقة.
    --- data = { matchId, killerUserId, killerName, victimUserId, victimName,
    ---          weapon, headshot (bool) }
    onKill = function(data)
    end,

    --- اللاعب دخل أو خرج من طابور الرانكد.
    --- data = { userId, name, mode, partySize, autoFill (bool) }
    onQueueJoin = function(data)
    end,
    onQueueLeave = function(data)
    end,

    --- رانك اللاعب تغيّر، من قيم أو من إعطاء إداري.
    --- data = { userId, name, from = { id, name }, to = { id, name }, rp, promoted (bool) }
    onRankChange = function(data)
        -- مثال: اعطِ قروب vRP عند رانك معيّن
        -- if data.to.name == 'Radiant' then
        --     vRP.addUserGroup({ data.userId, 'radiant' })
        -- end
    end
}
