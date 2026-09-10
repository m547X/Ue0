Config                  = {}

Config.Debug            = false          -- true يطبع رسائل تتبّع بكونسول السيرفر
Config.ServerName       = 'M5 Competitive' -- اسم السيرفر الي يطلع بالواجهة
Config.DefaultLocale    = 'en'           -- اللغة الافتراضية للنصوص

-- ============================================================================
-- ١. الفريم ورك (vRP)
-- ============================================================================

Config.vRP              = {
    -- إضافة خيار داخل قائمة vRP الرئيسية
    registerMenu = {
        enabled     = true, -- تشغيل الخيار
        menu        = 'main', -- اسم القائمة الي ينضاف لها
        name        = '! الرانك !', -- اسم الخيار بالقائمة
        description = 'M5 Ranked PvP — Competitive Hub' -- وصفه
    }

    -- الأسماء المعروضة تجي من GetPlayerName بس. الدالة vRP.getUserIdentity
    -- تشتغل بـ callback وما تقدر ترجّع نتيجة عبر الـ Proxy المتزامن، فما هي
    -- مستخدمة بأي مكان بهذا السكربت وهذا مقصود.
}

-- ============================================================================
-- ٢. قاعدة البيانات (oxmysql)
-- ============================================================================

Config.Database         = {
    tablePrefix          = 'm5_', -- بادئة أسماء الجداول
    autoCreateTables     = true,  -- ينشئ الجداول عند تشغيل السكربت إذا كانت ناقصة
    -- كتابة مجمّعة: الإحصائيات تنكتب كل هذي المدة بدل كل حدث لحاله.
    flushInterval        = 30000, -- ملي ثانية
    -- مدة صلاحية الكاش للبيانات الي تنقرأ كثير وتتغير قليل
    leaderboardCacheTime = 60000, -- ملي ثانية
    profileCacheTime     = 30000, -- ملي ثانية
    -- عدد الصفوف بكل صفحة من لوحة الصدارة والسجل
    pageSize             = 25,
    historyPageSize      = 12,
    -- أكثر عدد صفوف ينحفظ بسجل القتل لكل قيم (حماية من السبام)
    maxKillRowsPerMatch  = 800
}

-- ============================================================================
-- ٣. الصلاحيات (نصوص صلاحيات vRP)
-- ============================================================================

Config.Permissions      = {
    -- ------------------------------------------------------------------
    -- الصلاحية العليا
    -- الي يملكها يقدر يسوي كل أوامر الإدارة تحت بدون ما يحتاج أي صلاحية
    -- منفصلة. لا تعطيها إلا لصاحب السيرفر.
    -- ------------------------------------------------------------------
    superAdmin     = 'pvp.all',

    -- امتلاك صلاحية الإدارة العامة كمان يفتح كل الأوامر.
    -- خلّها false إذا تبي تحكّم دقيق لكل أمر حتى على الإداريين.
    adminGrantsAll = true,

    -- ---- اللعب --------------------------------------------------------
    openMenu       = 'pvp.menu',         -- فتح الواجهة
    createCustom   = 'pvp.custom.create', -- إنشاء غرفة خاصة
    spectate       = 'pvp.spectate',     -- المشاهدة
    viewMMR        = 'pvp.mmr',          -- رؤية الـ MMR المخفي

    -- ---- درجات الطاقم --------------------------------------------------
    -- المشرف: يفتح لوحة الإدارة بوضع قراءة فقط إلا إذا انعطى أكثر
    -- الإداري: طاقم كامل، حسب إعداد adminGrantsAll
    moderator      = 'pvp.moderator',
    admin          = 'pvp.admin',

    -- ---- أسماء قديمة (باقية عشان الإعدادات القديمة تضل تشتغل) ---------
    manageBans     = 'pvp.bans',
    manageSeasons  = 'pvp.seasons',
    manageRewards  = 'pvp.rewards',
    manageMaps     = 'pvp.maps',
    modifyRP       = 'pvp.rp.modify'
}

-- ============================================================================
-- ٣ب. أوامر الإدارة — صلاحية لكل أمر
-- ============================================================================
-- كل خيار داخل لوحة الإدارة معرّف هنا. السيرفر يرفض أي أمر ما يملك صاحبه
-- صلاحيته، واللوحة ما ترسم إلا الأزرار الي يقدر يستخدمها.
--
--   permission : نص صلاحية vRP المطلوبة للأمر
--   label      : الي يطلع باللوحة وبسجل التدقيق
--   reason     : true = السبب إجباري
--   confirm    : true = اللوحة تطلب تأكيد أول
--   group      : أي قسم باللوحة ينحط فيه الزر

Config.AdminActions     = {
    -- ---- المراقبة ------------------------------------------------------
    dashboard     = { permission = 'pvp.admin.view', label = 'View Dashboard', group = 'monitor' },
    playerLookup  = { permission = 'pvp.admin.view', label = 'Player Lookup', group = 'monitor' },
    spectate      = { permission = 'pvp.admin.spectate', label = 'Spectate Match', group = 'monitor' },
    stopSpectate  = { permission = 'pvp.admin.spectate', label = 'Stop Spectating', group = 'monitor' },

    -- ---- التحكم بالقيم -------------------------------------------------
    endMatch      = { permission = 'pvp.admin.match.end', label = 'Force End Match', group = 'match', confirm = true, reason = true },
    restartRound  = { permission = 'pvp.admin.match.round', label = 'Restart Round', group = 'match' },
    movePlayer    = { permission = 'pvp.admin.match.move', label = 'Move Player Team', group = 'match' },
    kickFromMatch = { permission = 'pvp.admin.match.kick', label = 'Kick From Match', group = 'match', reason = true },
    closeRoom     = { permission = 'pvp.admin.custom.close', label = 'Close Custom Room', group = 'match', confirm = true },
    freeze        = { permission = 'pvp.admin.freeze', label = 'Freeze Ranked Queue', group = 'match', confirm = true },
    startBotMatch = { permission = 'pvp.admin.botmatch', label = 'Start Bot Match', group = 'match' },
    stopBotMatch  = { permission = 'pvp.admin.botmatch', label = 'Stop Bot Match', group = 'match' },

    -- ---- النقاط ---------------------------------------------------------
    addRP         = { permission = 'pvp.admin.rp.add', label = 'Compensate RP', group = 'points', reason = true },
    removeRP      = { permission = 'pvp.admin.rp.remove', label = 'Deduct RP', group = 'points', reason = true },
    setRP         = { permission = 'pvp.admin.rp.set', label = 'Set RP', group = 'points', reason = true },
    setRank       = { permission = 'pvp.admin.rank.set', label = 'Set Rank', group = 'points', reason = true },
    addXP         = { permission = 'pvp.admin.xp', label = 'Grant XP', group = 'points', reason = true },
    giveCoins     = { permission = 'pvp.admin.coins', label = 'Give Coins', group = 'points', reason = true },
    takeCoins     = { permission = 'pvp.admin.coins', label = 'Take Coins', group = 'points', reason = true },
    resetStats    = { permission = 'pvp.admin.stats.reset', label = 'Reset Season Stats', group = 'points', confirm = true, reason = true },

    -- ---- العقوبات -------------------------------------------------------
    ban           = { permission = 'pvp.admin.ban', label = 'Ranked Ban', group = 'punish', reason = true },
    unban         = { permission = 'pvp.admin.unban', label = 'Remove Ranked Ban', group = 'punish' },
    clearCooldown = { permission = 'pvp.admin.cooldown', label = 'Clear Queue Cooldown', group = 'punish' },
    reviewFlag    = { permission = 'pvp.admin.antiboost', label = 'Review Anti-Boost Flag', group = 'punish' },

    -- ---- النظام ---------------------------------------------------------
    newSeason     = { permission = 'pvp.admin.season', label = 'Start New Season', group = 'system', confirm = true },
    toggleMode    = { permission = 'pvp.admin.mode', label = 'Enable / Disable Mode', group = 'system' },
    auditLog      = { permission = 'pvp.admin.audit', label = 'View Audit Log', group = 'system' }
}

-- حدود على تعديل النقاط، عشان غلطة كتابة ما تخرّب الترتيب.
Config.AdminLimits      = {
    maxRPGrant         = 2000, -- أكثر RP بعملية إضافة وحدة
    maxRPDeduct        = 2000, -- أكثر RP بعملية خصم وحدة
    maxXPGrant         = 100000, -- أكثر XP بعملية وحدة
    maxCoinGrant       = 100000, -- أكثر كوينز بعملية إعطاء أو سحب وحدة
    reasonMinLen       = 3, -- أقصر سبب مقبول
    reasonMaxLen       = 200, -- أطول سبب مقبول
    -- كم يوم ينحفظ سجل التدقيق (0 = للأبد)
    auditRetentionDays = 90
}

-- إذا true أي لاعب يقدر يفتح القائمة (صلاحية openMenu تنتجاهل)
Config.PublicMenu       = true

-- ============================================================================
-- ٤. ويب هوك الديسكورد
-- ============================================================================
-- خلّ القيمة فاضية ('') إذا ما تبي هذا اللوق.

Config.Webhooks         = {
    enabled       = true,        -- تشغيل اللوقات

    botName       = 'M5 Ranked PvP', -- الاسم الي يطلع فيه البوت
    avatar        = '',          -- رابط صورة البوت
    -- اللوقات تنجمّع وتنرسل دفعات عشان ما يوقفنا الديسكورد.
    batchInterval = 4000,        -- ملي ثانية بين كل دفعة
    maxQueue      = 400,         -- أكثر عدد لوقات ينتظر بالطابور

    urls          = {
        matchStart   = '', -- بداية قيم
        matchEnd     = '', -- نهاية قيم
        rpGain       = '', -- ربح RP
        rpLoss       = '', -- خسارة RP
        rankUp       = '', -- ترقية رانك
        rankDown     = '', -- نزول رانك
        leave        = '', -- خروج من قيم
        afk          = '', -- طرد خمول
        rankBan      = '', -- حظر من الرانكد
        unban        = '', -- فك الحظر
        rpModify     = '', -- تعديل RP إداري
        customGame   = '', -- الغرف الخاصة
        antiBoost    = '', -- بلاغات التبويست
        adminActions = '', -- أوامر الإدارة
        errors       = ''  -- الأخطاء
    },

    colors        = { -- لون كل نوع لوق بالديسكورد (رقم عشري)
        matchStart   = 3447003,
        matchEnd     = 3066993,
        rpGain       = 3066993,
        rpLoss       = 15158332,
        rankUp       = 16766720,
        rankDown     = 10038562,
        leave        = 15158332,
        afk          = 15105570,
        rankBan      = 10038562,
        unban        = 3066993,
        rpModify     = 16776960,
        customGame   = 2123412,
        antiBoost    = 15158332,
        adminActions = 9807270,
        errors       = 16711680
    }
}

-- ============================================================================
-- ٥. الرانكات
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ٥أ. مجمّعات الرانك — رانك مستقل لكل طور
-- ----------------------------------------------------------------------------
-- المجمّع هو سلّم مستقل بذاته: له RP ورانك ومباريات تحديد و MMR مخفي خاصة فيه.
-- إذا `perMode` مشغّل، كل طور يصير سلّم لحاله، فيقدر اللاعب يكون قولد بـ 1v1
-- وسيلفر بـ 2v2 بنفس الوقت.
--
-- `shared` يجمّع الأطوار الي تبيها تنحسب سلّم واحد. أي طور مو مكتوب يضل لحاله.
-- مثال إذا تبي كل أطوار الفرق على سلّم واحد:
--
--     shared = { ['2v2'] = 'team', ['3v3'] = 'team', ['5v5'] = 'team' }
--
-- تغيير هذي الإعدادات يعيد تجميع الرانكات الموجودة. المجمّع ينحفظ باسمه، فإذا
-- غيّرت الاسم تبقى الصفوف القديمة تحت الاسم القديم واللاعبين يبدون من Unranked
-- بذاك المجمّع. قرّر التجميع قبل ما تفتح السيرفر.
--
Config.RankPools        = {
    -- false = سلّم واحد لكل شي، زي ما كان قبل الرانك المنفصل لكل طور. وقتها كل
    -- الأطوار تستخدم `default` تحت.
    perMode = true,

    shared = {
        -- ['tdm'] = 'objective',
        -- ['snd'] = 'objective',
    },

    -- يطلع بالواجهة قبل ما يختار اللاعب طور، ويستخدم كسلّم وحيد إذا perMode
    -- مطفي.
    default = '1v1',

    -- وين تروح الرانكات المحفوظة قبل ما يوجد الرانك لكل طور. الترقية تختم كل
    -- صف قديم بهذا المجمّع، فما أحد يفقد رانكه. لازم يكون واحد من مجمّعاتك،
    -- وغالباً نفس `default`.
    legacy = '1v1'
}

-- `rpRequired` هو مجموع الـ RP المطلوب عشان تدخل هذي الدرجة.
-- الترتيب مهم: القائمة لازم تكون مرتبة تصاعدياً حسب rpRequired.

Config.Ranks            = {
    { id = 0,  tier = 'UNRANKED',  division = 0, name = 'Unranked',      rpRequired = 0,    color = '#5A616D' },

    { id = 1,  tier = 'IRON',      division = 1, name = 'Iron I',        rpRequired = 0,    color = '#7C7C80' },
    { id = 2,  tier = 'IRON',      division = 2, name = 'Iron II',       rpRequired = 100,  color = '#7C7C80' },
    { id = 3,  tier = 'IRON',      division = 3, name = 'Iron III',      rpRequired = 200,  color = '#7C7C80' },

    { id = 4,  tier = 'BRONZE',    division = 1, name = 'Bronze I',      rpRequired = 300,  color = '#A3703C' },
    { id = 5,  tier = 'BRONZE',    division = 2, name = 'Bronze II',     rpRequired = 400,  color = '#A3703C' },
    { id = 6,  tier = 'BRONZE',    division = 3, name = 'Bronze III',    rpRequired = 500,  color = '#A3703C' },

    { id = 7,  tier = 'SILVER',    division = 1, name = 'Silver I',      rpRequired = 600,  color = '#B9C1CC' },
    { id = 8,  tier = 'SILVER',    division = 2, name = 'Silver II',     rpRequired = 700,  color = '#B9C1CC' },
    { id = 9,  tier = 'SILVER',    division = 3, name = 'Silver III',    rpRequired = 800,  color = '#B9C1CC' },

    { id = 10, tier = 'GOLD',      division = 1, name = 'Gold I',        rpRequired = 900,  color = '#E8B33C' },
    { id = 11, tier = 'GOLD',      division = 2, name = 'Gold II',       rpRequired = 1000, color = '#E8B33C' },
    { id = 12, tier = 'GOLD',      division = 3, name = 'Gold III',      rpRequired = 1100, color = '#E8B33C' },

    { id = 13, tier = 'PLATINUM',  division = 1, name = 'Platinum I',    rpRequired = 1200, color = '#37C2D8' },
    { id = 14, tier = 'PLATINUM',  division = 2, name = 'Platinum II',   rpRequired = 1300, color = '#37C2D8' },
    { id = 15, tier = 'PLATINUM',  division = 3, name = 'Platinum III',  rpRequired = 1400, color = '#37C2D8' },

    { id = 16, tier = 'DIAMOND',   division = 1, name = 'Diamond I',     rpRequired = 1500, color = '#8E6BFF' },
    { id = 17, tier = 'DIAMOND',   division = 2, name = 'Diamond II',    rpRequired = 1620, color = '#8E6BFF' },
    { id = 18, tier = 'DIAMOND',   division = 3, name = 'Diamond III',   rpRequired = 1740, color = '#8E6BFF' },

    { id = 19, tier = 'ASCENDANT', division = 1, name = 'Ascendant I',   rpRequired = 1860, color = '#22C97C' },
    { id = 20, tier = 'ASCENDANT', division = 2, name = 'Ascendant II',  rpRequired = 1990, color = '#22C97C' },
    { id = 21, tier = 'ASCENDANT', division = 3, name = 'Ascendant III', rpRequired = 2120, color = '#22C97C' },

    { id = 22, tier = 'IMMORTAL',  division = 0, name = 'Immortal',      rpRequired = 2260, color = '#E0304E' },
    { id = 23, tier = 'RADIANT',   division = 0, name = 'Radiant',       rpRequired = 2600, color = '#FFE9A8' }
}

-- ترتيب درجات الرانك الي يستخدمه مسار التقدّم بالواجهة
Config.RankPath         = {
    'IRON', 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM',
    'DIAMOND', 'ASCENDANT', 'IMMORTAL', 'RADIANT'
}

Config.RankSettings     = {
    -- أرضية الـ RP: اللاعب ما ينزل تحت الـ RP الأساسي لدرجته
    demotionProtection   = true,
    -- كم قيم بعد الترقية ما ينزل فيها الرانك
    rankProtectionGames  = 2,
    -- بعد N خسارات متتالية تنقص خسارة الـ RP بهذا المعامل
    loseStreakProtection = { enabled = true, afterLosses = 3, lossMultiplier = 0.6 },
    -- رانك Radiant محدود بأفضل N لاعب بالموسم (0 = بلا حد)
    radiantSlots         = 25,
    -- حدود الـ RP المطلقة
    minRP                = 0,
    maxRP                = 9999
}

-- ============================================================================
-- ٦. نقاط الرانك (RP)
-- ============================================================================

Config.RankedPoints     = {
    winBase            = 20, -- الأساس الي تاخذه بالفوز
    lossBase           = 18, -- الأساس الي تخسره بالخسارة

    minimumGain        = 8,  -- أقل ربح ممكن بالفوز
    maximumGain        = 40, -- أكثر ربح ممكن بالفوز

    minimumLoss        = 5,  -- أقل خسارة ممكنة
    maximumLoss        = 45, -- أكثر خسارة ممكنة

    mvpBonus           = 5,  -- زيادة لأفضل لاعب بالقيم
    headshotBonusLimit = 4,  -- أكثر زيادة تجي من الهيدشوتات

    winStreakBonus     = 3,  -- زيادة على سلسلة الانتصارات

    leavePenalty       = 35, -- خصم الخروج من القيم
    afkPenalty         = 25, -- خصم الخمول

    -- ------------------------------------------------------------------
    -- نموذج الأداء الموزون.
    -- الـ RP النهائي = الأساس ± فرق الراوندات ± فرق المستوى + الأداء + الزيادات
    -- ------------------------------------------------------------------
    weights            = {
        -- فرق الراوندات (السيطرة). كل راوند فرق يزيد أو ينقص RP.
        roundDiffPerRound    = 1.2, -- كم RP لكل راوند فرق
        roundDiffMax         = 8,  -- أكثر شي يعطيه فرق الراوندات

        -- قوة الخصم: (متوسط MMR الخصم - متوسط MMR فريقك) / mmrScale * المعامل
        mmrScale             = 100,
        mmrFactorWin         = 4.0, -- الفوز على فرق أقوى يعطي أكثر
        mmrFactorLoss        = 3.0, -- الخسارة أمام فرق أقوى تكلّف أقل

        -- فرق الرانك (متوسط رانك الخصم - رانكك)
        rankGapFactor        = 0.8,
        rankGapMax           = 6,

        -- أداءك الشخصي مقارنة بمتوسط اللوبي (منسّق من 0.0 إلى 2.0)
        kdWeight             = 3.0, -- وزن نسبة القتل للموت
        killsWeight          = 2.5, -- وزن عدد القتلات
        damageWeight         = 2.0, -- وزن الضرر
        headshotWeight       = 1.5, -- وزن الهيدشوتات
        clutchWeight         = 1.5, -- وزن الحسم وأنت آخر واحد
        objectiveWeight      = 1.5, -- وزن الأهداف (زرع/تفكيك)

        -- نصيبك من نقاط فريقك (نقاطك / نقاط الفريق)
        teamShareWeight      = 2.0,

        -- معامل توازن القيم: القيم غير المتوازنة تسوى أقل
        unbalancedPenalty    = 0.75,
        balancedThresholdMMR = 250, -- فرق MMR الي فوقه تنحسب غير متوازنة

        -- الأداء ما يقدر يقلب النتيجة بالعكس أبداً
        maxPerformanceBonus  = 12, -- أكثر زيادة من الأداء
        maxPerformanceMalus  = 10 -- أكثر خصم من الأداء
    },

    -- مباريات التحديد ما تعطي RP لكن تبني الـ MMR
    placementRPPerWin  = 0,
    -- RP إضافي على سلاسل الفوز القصيرة (المفتاح = طول السلسلة)
    streakTable        = { [3] = 3, [5] = 6, [8] = 9, [12] = 12 },

    -- الغرف الخاصة ما تعطي RP إلا إذا فعّلت Config.CustomGames.rankedAllowed
    customGameRP       = false
}

-- ============================================================================
-- ٧. الـ MMR (مخفي)
-- ============================================================================

Config.MMR              = {
    startValue        = 1000, -- الي يبدأ فيه اللاعب الجديد
    min               = 100, -- أقل قيمة
    max               = 5000, -- أكثر قيمة

    -- معامل K على طريقة إيلو، ينضبط حسب الثقة بالتقييم
    kBase             = 32,
    kPlacement        = 64,   -- وقت مباريات التحديد
    kHighRank         = 20,   -- فوق حد الرانك العالي
    highRankThreshold = 2000, -- حد الرانك العالي

    -- عدم اليقين ينقص كل ما لعب اللاعب أكثر
    uncertaintyStart  = 350, -- البداية
    uncertaintyMin    = 60,  -- الحد الأدنى
    uncertaintyDecay  = 12,  -- كم ينقص بعد كل قيم مكتملة

    -- تأثير الأداء على الـ MMR (0 = إيلو فوز/خسارة صافي)
    performanceFactor = 0.35,

    -- الـ MMR يبين للطاقم فقط
    visibleTo         = 'admin' -- 'admin' أو 'moderator' أو 'none'
}

-- ============================================================================
-- ٨. مباريات التحديد
-- ============================================================================

Config.Placement        = {
    enabled = true, -- تشغيل مباريات التحديد
    matches = 5,    -- عددها قبل ما ينعطى رانك

    -- رقم الرانك الي ينعطى حسب درجة الأداء بعد التحديد
    -- الدرجة = مزيج موزون (نسبة الفوز، القتل/الموت، الهيدشوت، الضرر، MVP، قوة الخصم)
    resultTable = {
        { minScore = 0.00, rankId = 1 },  -- Iron I
        { minScore = 0.20, rankId = 3 },  -- Iron III
        { minScore = 0.32, rankId = 5 },  -- Bronze II
        { minScore = 0.42, rankId = 7 },  -- Silver I
        { minScore = 0.52, rankId = 9 },  -- Silver III
        { minScore = 0.60, rankId = 11 }, -- Gold II
        { minScore = 0.68, rankId = 13 }, -- Platinum I
        { minScore = 0.76, rankId = 15 }, -- Platinum III
        { minScore = 0.84, rankId = 16 }, -- Diamond I
        { minScore = 0.92, rankId = 18 }  -- Diamond III
    },

    -- أوزان حساب درجة التحديد
    weights = {
        winRate     = 0.40, -- نسبة الفوز
        kd          = 0.20, -- نسبة القتل للموت
        headshotPct = 0.12, -- نسبة الهيدشوت
        damage      = 0.13, -- الضرر
        mvp         = 0.07, -- مرات أفضل لاعب
        opponentMMR = 0.08  -- قوة الخصوم
    }
}

-- ============================================================================
-- ٩. أطوار اللعب
-- ============================================================================

Config.Modes            = {

    ['1v1'] = {
        label        = '1V1',
        description  = 'Pure aim duel. First to 7 rounds.',
        teamSize     = 1,       -- عدد اللاعبين بالفريق الواحد
        teams        = 2,       -- عدد الفرق
        ranked       = true,    -- يحسب رانك ولا لا
        type         = 'rounds', -- rounds أو deathmatch أو ffa أو snd
        rounds       = 13,      -- أكثر عدد راوندات
        roundsToWin  = 7,       -- كم راوند تحتاج عشان تفوز
        roundTime    = 90,      -- وقت الراوند بالثواني
        matchTime    = 1800,    -- أقصى وقت للقيم كلها بالثواني
        killLimit    = 0,       -- حد القتلات (0 = بلا حد)
        respawn      = false,   -- رسبن داخل الراوند
        lives        = 1,       -- عدد الأرواح بالراوند
        friendlyFire = false,   -- ضرر الزملاء
        overtime     = true,    -- وقت إضافي عند التعادل
        suddenDeath  = true,    -- راوند حاسم بالنهاية
        loadout      = 'duel',  -- اسم السلاح من Config.Loadouts
        enabled      = true     -- تشغيل الطور
    },

    ['2v2'] = {
        label = '2V2',
        description = 'Duo tactical rounds.',
        teamSize = 2,
        teams = 2,
        ranked = true,
        type = 'rounds',
        rounds = 13,
        roundsToWin = 7,
        roundTime = 100,
        matchTime = 2400,
        killLimit = 0,
        respawn = false,
        lives = 1,
        friendlyFire = false,
        overtime = true,
        suddenDeath = true,
        loadout = 'standard',
        enabled = true
    },

    ['3v3'] = {
        label = '3V3',
        description = 'Trio competitive rounds.',
        teamSize = 3,
        teams = 2,
        ranked = true,
        type = 'rounds',
        rounds = 13,
        roundsToWin = 7,
        roundTime = 110,
        matchTime = 2700,
        killLimit = 0,
        respawn = false,
        lives = 1,
        friendlyFire = false,
        overtime = true,
        suddenDeath = true,
        loadout = 'standard',
        enabled = true
    },

    ['4v4'] = {
        label = '4V4',
        description = 'Squad rounds.',
        teamSize = 4,
        teams = 2,
        ranked = true,
        type = 'rounds',
        rounds = 15,
        roundsToWin = 8,
        roundTime = 120,
        matchTime = 3000,
        killLimit = 0,
        respawn = false,
        lives = 1,
        friendlyFire = false,
        overtime = true,
        suddenDeath = true,
        loadout = 'standard',
        enabled = true
    },

    ['5v5'] = {
        label = '5V5',
        description = 'The flagship competitive mode.',
        teamSize = 5,
        teams = 2,
        ranked = true,
        type = 'rounds',
        rounds = 25,
        roundsToWin = 13,
        roundTime = 120,
        matchTime = 3600,
        killLimit = 0,
        respawn = false,
        lives = 1,
        friendlyFire = false,
        overtime = true,
        suddenDeath = true,
        loadout = 'standard',
        enabled = true
    },

    ['ffa'] = {
        label = 'FREE FOR ALL',
        description = 'Everyone for themselves.',
        teamSize = 1,
        teams = 8,
        ranked = true,
        type = 'ffa',
        rounds = 1,
        roundsToWin = 1,
        roundTime = 600,
        matchTime = 600,
        killLimit = 30,
        respawn = true,
        respawnTime = 3,
        lives = 0,
        friendlyFire = true,
        overtime = false,
        suddenDeath = false,
        loadout = 'standard',
        minPlayers = 4,
        maxPlayers = 12,
        enabled = true
    },

    ['tdm'] = {
        label = 'TEAM DEATHMATCH',
        description = 'Team based kill race.',
        teamSize = 5,
        teams = 2,
        ranked = true,
        type = 'deathmatch',
        rounds = 1,
        roundsToWin = 1,
        roundTime = 600,
        matchTime = 600,
        killLimit = 75,
        respawn = true,
        respawnTime = 4,
        lives = 0,
        friendlyFire = false,
        overtime = true,
        suddenDeath = false,
        loadout = 'standard',
        enabled = true
    },

    ['snd'] = {
        label = 'SEARCH & DESTROY',
        description = 'Plant or defuse. No respawns.',
        teamSize = 5,
        teams = 2,
        ranked = true,
        type = 'snd',
        rounds = 13,
        roundsToWin = 7,
        roundTime = 135,
        matchTime = 3600,
        killLimit = 0,
        respawn = false,
        lives = 1,
        friendlyFire = false,
        overtime = true,
        suddenDeath = true,
        loadout = 'standard',
        plantTime = 4,
        defuseTime = 6,
        bombTimer = 40,
        enabled = true
    }
}

-- الأطوار الي تنعرض داخل طابور الرانكد (نفس الترتيب يطلع بالواجهة)
Config.RankedQueueModes = { '1v1', '2v2', '3v3', '5v5', 'tdm', 'snd' }

-- ============================================================================
-- ٩ب. سلوك طابور القروب
-- ============================================================================
-- يتحكم بكيف يتصرف طابور الرانكد حسب عدد قروبك.

Config.PartyQueue       = {

    -- الطور المختار يتبع عدد القروب تلقائياً: ادعُ صديق وأنت على 1V1 والطابور
    -- يتحوّل 2V2، وثالث يخليه 3V3، وهكذا. خلّه false إذا تبي يضل على الي
    -- اختاره اللاعب.
    autoMode = true,

    -- يقفل الطابور على الطور الي يطابق عدد القروب بالضبط.
    --   true  : قروب من ٢ ما يقدر يبحث إلا 2V2
    --   false : قروب من ٢ يقدر يبحث 2V2 وأي طور أكبر (3V3، 5V5 ...)،
    --           والأماكن الناقصة يعبيها الماتش ميكينق
    lockToPartySize = true,

    -- الأطوار الي حجم فريقها أصغر من قروبك ما ينبحث لها أبداً، مهما كان
    -- الإعداد فوق (قروب من ٣ ما يقدر يلعب 1V1).

    -- ---- الأوتو فيل ----------------------------------------------------
    -- خيار يشغّله اللاعب تحت زر البحث. إذا شغّله، الأطوار الي تحتاج عدد أكثر
    -- من عددهم تنفك من القفل: الواحد لحاله يقدر يبحث 3V3، والاثنين يقدرون
    -- يبحثون 5V5، والماتش ميكينق يحط لاعبين غرباء بالأماكن الفاضية بجهتهم.
    -- نفس تأثير lockToPartySize = false بالضبط، بس كل لاعب يختاره لنفسه بدل
    -- ما السيرفر يقرره على الكل.
    --
    -- وما يدخّل أحد بطور أصغر من قروبه أبداً: قروب من ثلاثة يضل ما يقدر يبحث
    -- 1V1، سواء الخيار مشغّل أو مطفي.
    autoFill = {
        -- false يخفي الخيار ويرفضه حتى لو طلبه الكلنت، فيصير lockToPartySize
        -- هو الوحيد الي يقرر.
        enabled = true,

        -- هل يبدأ مشغّل للاعب ما لمسه أبداً. بعدها اختياره هو ينحفظ له.
        default = false
    },

    -- كيف ينبني الفريق المقابل.
    teamMatching = {
        -- 'any'      : فريق الخصم ينبني من أي أحد منتظر — قروب ثاني، ولا
        --              اثنين لحالهم، ولا قروب من اثنين وواحد، وهكذا.
        -- 'fullTeam' : القروب الكامل ما يواجه إلا قروب كامل مثله. قروب من
        --              اثنين يبحث 2V2 ينتظر قروب ثاني من اثنين يبحث 2V2 بدل
        --              ما ينعطى لاعبين لحالهم، والي لحالهم يضلون يتطابقون
        --              بينهم عادي.
        mode = 'fullTeam',

        -- إذا ما جا فريق كامل مناسب خلال هذي الثواني، ينتطابق القروب بالطريقة
        -- العادية بدل ما ينتظر للأبد.
        -- 0 = ما فيه تراجع أبداً، ينتظر فريق حقيقي.
        fallbackAfter = 60
    }
}

-- ============================================================================
-- ١٠. الأسلحة الي ينزل فيها اللاعب
-- ============================================================================

Config.Loadouts         = {
    duel = {          -- سلاح المبارزة (1v1)
        health  = 100, -- الدم عند النزول
        armor   = 0,  -- الدرع عند النزول
        weapons = {
            { name = 'WEAPON_PISTOL',       ammo = 250 },
            { name = 'WEAPON_CARBINERIFLE', ammo = 300 }
        }
    },
    standard = { -- السلاح العادي لأغلب الأطوار
        health  = 100,
        armor   = 0,
        weapons = {
            { name = 'WEAPON_PISTOL',       ammo = 250 },
            { name = 'WEAPON_CARBINERIFLE', ammo = 300 },
            { name = 'WEAPON_PUMPSHOTGUN',  ammo = 40 }
        }
    },
    sniper = { -- طور القنص
        health  = 100,
        armor   = 0,
        weapons = {
            { name = 'WEAPON_SNIPERRIFLE', ammo = 40 },
            { name = 'WEAPON_PISTOL',      ammo = 100 }
        }
    },
    pistol = { -- طور المسدس فقط
        health = 100,
        armor = 0,
        weapons = { { name = 'WEAPON_PISTOL', ammo = 200 } }
    },
    training = { -- ساحة التدريب
        health = 200,
        armor = 0,
        weapons = {
            { name = 'WEAPON_CARBINERIFLE', ammo = 2000 },
            { name = 'WEAPON_PISTOL',       ammo = 2000 },
            { name = 'WEAPON_SNIPERRIFLE',  ammo = 500 }
        }
    }
}

-- الأسلحة الي تنعرض كخيارات بواجهة الغرف الخاصة.
-- لازم يكون `weapon` موجود كمان بقائمة Config.Weapons.allowed تحت.
Config.WeaponPresets    = {
    { id = 'pistol_mk2',    label = 'Pistol MK2',    weapon = 'WEAPON_PISTOL_MK2',   ammo = 250 },
    { id = 'combat_mg',     label = 'Combat MG',     weapon = 'WEAPON_COMBATMG',     ammo = 400 },
    { id = 'assault_rifle', label = 'Assault Rifle', weapon = 'WEAPON_ASSAULTRIFLE', ammo = 300 },
    { id = 'sniper',        label = 'Sniper',        weapon = 'WEAPON_SNIPERRIFLE',  ammo = 50 },
    { id = 'shotgun',       label = 'Shotgun',       weapon = 'WEAPON_PUMPSHOTGUN',  ammo = 40 },
    { id = 'smg',           label = 'SMG',           weapon = 'WEAPON_SMG',          ammo = 250 },
    { id = 'knife',         label = 'Knife',         weapon = 'WEAPON_KNIFE',        ammo = 1 }
}

Config.Weapons          = {
    -- القائمة البيضاء العامة. أي سلاح مو مكتوب هنا ضرره ما ينحسب.
    allowed = {
        'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL',
        'WEAPON_APPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL',
        'WEAPON_SNSPISTOL', 'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMG_MK2',
        'WEAPON_ASSAULTSMG', 'WEAPON_COMBATPDW', 'WEAPON_MACHINEPISTOL',
        'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE',
        'WEAPON_CARBINERIFLE_MK2', 'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE',
        'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_PUMPSHOTGUN',
        'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_HEAVYSHOTGUN',
        'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE',
        'WEAPON_COMBATMG', 'WEAPON_MG', 'WEAPON_KNIFE', 'WEAPON_BAT',
        'WEAPON_UNARMED'
    },

    -- ممنوعة نهائياً، حتى لو حاولت غرفة خاصة تشغّلها
    blacklisted = {
        'WEAPON_RPG', 'WEAPON_GRENADELAUNCHER', 'WEAPON_MINIGUN',
        'WEAPON_FIREWORK', 'WEAPON_RAILGUN', 'WEAPON_HOMINGLAUNCHER',
        'WEAPON_COMPACTLAUNCHER', 'WEAPON_STICKYBOMB', 'WEAPON_PROXMINE',
        'WEAPON_PIPEBOMB', 'WEAPON_MOLOTOV', 'WEAPON_GRENADE',
        'WEAPON_RAYPISTOL', 'WEAPON_RAYCARBINE', 'WEAPON_RAYMINIGUN',
        'WEAPON_EMPLAUNCHER', 'WEAPON_FLARE', 'WEAPON_PETROLCAN'
    },

    -- معامل الضرر لكل لاعب داخل القيم (1.0 = زي اللعبة الأصلية)
    playerDamageModifier = 1.0,

    -- ضرر الانفجار والسيارة والسقوط ما ينحسب مصدر قتل أبداً
    invalidDamageSources = {
        'EXPLOSION', 'FALL', 'VEHICLE', 'DROWNING', 'FIRE', 'ELECTRIC'
    },

    -- أبعد مسافة معقولة لقتلة بالرصاص (متر).
    -- أبعد من كذا ينترفع بلاغ بس ما ينمنع، عشان ما تصير بلاغات كاذبة.
    maxPlausibleDistance = 600.0,

    -- أقل مدة (ملي ثانية) بين قتلتين معتمدتين من نفس المهاجم.
    minKillInterval = 120
}

-- ============================================================================
-- ١١. الهيدشوت — قتل بطلقة وحدة، بلا فرق مسافة
-- ============================================================================

Config.Headshot         = {
    enabled             = true, -- تشغيل نظام الهيدشوت

    oneShotKill         = true, -- طلقة الرأس تقتل على طول

    ignoreDistance      = true, -- من أي مسافة، بدون نقص ضرر

    enabledInRanked     = true, -- بالرانكد

    enabledInCustom     = true, -- بالغرف الخاصة

    enabledInTraining   = true, -- بالتدريب

    excludedWeapons     = {}, -- أسلحة مستثناة من القاعدة

    -- أرقام عظام الرأس المقبولة (SKEL_Head و HEAD_top وعظمة الهيدشوت).
    headBones           = { 31086, 39317, 12844, 20178, 21550 },

    -- نافذة تحقق السيرفر: لازم المهاجم يكون أطلق خلال هذي المدة (ملي ثانية)
    -- من لحظة إصابة الرأس المبلّغ عنها.
    shotWindow          = 900,

    -- نافذة منع التكرار لنفس المهاجم والضحية.
    duplicateWindow     = 400,

    -- حد المعدل: أكثر عدد بلاغات هيدشوت مقبولة من مهاجم واحد بالثانية.
    maxReportsPerSecond = 6,

    -- يرفض البلاغ إذا الضحية أصلاً ميت أو يرسبن
    requireVictimAlive  = true,

    -- أسلحة الطعن والضرب ما تفعّل قاعدة الطلقة الوحدة
    excludeMelee        = true
}

-- ============================================================================
-- ١٢. المابات
-- ============================================================================


Config.Maps             = {


    {
        id        = 'maincraft',
        name      = "ماين كرافت",
        image     = 'https://r2.fivemanage.com/EX1FJXysrxR5lQr7eorEh/Screenshot_147.png',
        center    = vector3(-1952.404, -1503.301, 321.060),
        radius    = 150.0,
        modes     = { '1v1', '2v2' },
        weapons   = nil,
        teamA     = {
            vector4(-1973.118, -1493.408, 321.061, 261.076)
        },
        teamB     = {
            vector4(-1929.014, -1514.050, 321.061, 85.310)
        },
        spectator = vector4(-1952.404, -1503.301, 346.060, 269.178)
    },

    {
        id        = 'airskate1',
        name      = "AIR SKATE 1",
        image     = 'https://r2.fivemanage.com/EX1FJXysrxR5lQr7eorEh/Screenshot_164.png',
        center    = vector3(-2101.788, -1785.290, 651.131),
        radius    = 150.0,
        modes     = { '1v1', '2v2', '3v3' },
        weapons   = nil,
        teamA     = {
            vector4(-2114.919, -1817.637, 655.929, 343.978)
        },
        teamB     = {
            vector4(-2110.082, -1762.764, 651.133, 189.471)
        },
        spectator = vector4(-2101.788, -1785.290, 676.131, 182.878)
    },

    {
        id        = 'airskate2',
        name      = "AIR SKATE 2",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/AirSkate2.png',
        center    = vector3(-3353.411, -815.803, 102.633),
        radius    = 150.0,
        modes     = { '1v1', '2v2', '3v3' },
        weapons   = nil,
        teamA     = {
            vector4(-3308.983, -824.315, 99.699, 84.775)
        },
        teamB     = {
            vector4(-3397.637, -805.618, 99.699, 257.385)
        },
        spectator = vector4(-3353.411, -815.803, 127.633, 270.663)
    },

    {
        id        = 'airskate3',
        name      = "AIR SKATE 3",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/AirSkate3.png',
        center    = vector3(-2912.725, -1034.516, 101.000),
        radius    = 150.0,
        modes     = { '2v2', '3v3', '4v4' },
        weapons   = nil,
        teamA     = {
            vector4(-2921.795, -1062.875, 101.000, 344.512)
        },
        teamB     = {
            vector4(-2904.417, -1009.851, 101.000, 164.998)
        },
        spectator = vector4(-2912.725, -1034.516, 126.000, 358.193)
    },

    {
        id        = 'arena1',
        name      = "ARENA 1",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Arena1.png',
        center    = vector3(5367.149, -1110.734, 355.209),
        radius    = 155.0,
        modes     = { '2v2', '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(5365.400, -1054.133, 355.209, 171.379),
            vector4(5371.000, -1058.000, 355.209, 165.000),
            vector4(5360.000, -1050.000, 355.209, 175.000)
        },
        teamB     = {
            vector4(5362.789, -1157.215, 355.209, 359.840),
            vector4(5358.000, -1162.000, 355.209, 355.000),
            vector4(5366.500, -1153.000, 355.209, 4.000)
        },
        spectator = vector4(5367.149, -1110.734, 380.209, 2.671)
    },

    {
        id        = 'arena2',
        name      = "ARENA 2",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Arena2.png',
        center    = vector3(4053.109, 0.296, 195.994),
        radius    = 160.0,
        modes     = { '2v2', '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(3989.586, -6.934, 195.994, 276.539)
        },
        teamB     = {
            vector4(4106.084, -4.232, 195.994, 95.518)
        },
        spectator = vector4(4053.109, 0.296, 220.994, 255.171)
    },

    {
        id        = 'arena3',
        name      = "ARENA 3",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Arena3.png',
        center    = vector3(-147.057, -4347.000, 191.805),
        radius    = 165.0,
        modes     = { '2v2', '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(-211.899, -4348.358, 191.501, 267.509)
        },
        teamB     = {
            vector4(-83.160, -4347.987, 191.501, 90.946)
        },
        spectator = vector4(-147.057, -4347.000, 216.805, 95.589)
    },

    {
        id        = 'arena4',
        name      = "ARENA 4",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Arena4.png',
        center    = vector3(4400.804, 2800.000, 548.195),
        radius    = 150.0,
        modes     = { '2v2', '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(4384.621, 2830.983, 549.169, 208.419)
        },
        teamB     = {
            vector4(4421.670, 2768.009, 549.168, 27.544)
        },
        spectator = vector4(4400.804, 2800.000, 573.195, 89.810)
    },

    {
        id        = 'arena5',
        name      = "ARENA 5",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Arena5.png',
        center    = vector3(4014.105, 1311.000, 678.667),
        radius    = 150.0,
        modes     = { '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(3985.851, 1344.412, 679.641, 229.956)
        },
        teamB     = {
            vector4(4044.031, 1290.699, 679.641, 62.625)
        },
        spectator = vector4(4014.105, 1311.000, 703.667, 265.684)
    },

    {
        id        = 'arena6',
        name      = "ARENA 6",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Arena6.png',
        center    = vector3(4278.000, 1483.000, 678.663),
        radius    = 150.0,
        modes     = { '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(4301.730, 1449.314, 679.641, 33.482)
        },
        teamB     = {
            vector4(4260.077, 1515.170, 679.641, 199.076)
        },
        spectator = vector4(4278.000, 1483.000, 703.663, 62.279)
    },

    {
        id        = 'csspy',
        name      = "CS SPY",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/CSSPY.png',
        center    = vector3(-3543.997, 1358.995, 310.357),
        radius    = 150.0,
        modes     = { '2v2', '3v3', '4v4' },
        weapons   = nil,
        teamA     = {
            vector4(-3560.441, 1361.208, 310.361, 272.545)
        },
        teamB     = {
            vector4(-3529.229, 1361.143, 310.361, 92.474)
        },
        spectator = vector4(-3543.997, 1358.995, 335.357, 198.740)
    },

    {
        id        = 'dust',
        name      = "DUST",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Dust.png',
        center    = vector3(-3180.145, -348.759, 556.591),
        radius    = 150.0,
        modes     = { '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(-3181.165, -365.372, 556.530, 4.052)
        },
        teamB     = {
            vector4(-3180.019, -331.783, 556.530, 176.138)
        },
        spectator = vector4(-3180.145, -348.759, 581.591, 126.360)
    },

    {
        id        = 'helizone1',
        name      = "HELIZONE 1",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Helizone1.png',
        center    = vector3(1830.628, -3152.800, 399.520),
        radius    = 165.0,
        modes     = { '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(1862.077, -3193.385, 397.720, 32.101)
        },
        teamB     = {
            vector4(1796.781, -3096.550, 397.720, 216.662)
        },
        spectator = vector4(1830.628, -3152.800, 424.520, 357.470)
    },

    {
        id        = 'helizone2',
        name      = "HELIZONE 2",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Helizone2.png',
        center    = vector3(-2559.248, -1404.797, 419.369),
        radius    = 150.0,
        modes     = { '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(-2607.187, -1380.811, 420.467, 236.369)
        },
        teamB     = {
            vector4(-2516.310, -1427.585, 419.369, 65.272)
        },
        spectator = vector4(-2559.248, -1404.797, 444.369, 89.565)
    },

    {
        id        = 'lego',
        name      = "LEGO",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Lego.png',
        center    = vector3(-2360.094, -1154.271, 328.661),
        radius    = 150.0,
        modes     = { '1v1', '2v2', '3v3' },
        weapons   = nil,
        teamA     = {
            vector4(-2375.008, -1154.197, 328.661, 267.510)
        },
        teamB     = {
            vector4(-2344.829, -1154.091, 328.661, 93.119)
        },
        spectator = vector4(-2360.094, -1154.271, 353.661, 182.057)
    },

    {
        id        = 'neon1',
        name      = "NEON 1",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Neon1.png',
        center    = vector3(-2446.467, -1810.070, 100.366),
        radius    = 150.0,
        modes     = { '2v2', '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(-2397.956, -1843.997, 100.366, 2.390)
        },
        teamB     = {
            vector4(-2488.829, -1772.787, 100.366, 177.706)
        },
        spectator = vector4(-2446.467, -1810.070, 125.366, 271.634)
    },

    {
        id        = 'neon2',
        name      = "NEON 2",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Neon2.png',
        center    = vector3(-230.341, -3398.187, 558.460),
        radius    = 155.0,
        modes     = { '2v2', '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(-276.366, -3359.641, 558.460, 181.054)
        },
        teamB     = {
            vector4(-185.726, -3431.047, 558.460, 2.256)
        },
        spectator = vector4(-230.341, -3398.187, 583.460, 300.476)
    },

    {
        id        = 'neon3',
        name      = "NEON 3",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Neon3.png',
        center    = vector3(-2179.281, -2369.165, 500.729),
        radius    = 155.0,
        modes     = { '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(-2129.834, -2404.000, 500.729, 6.108)
        },
        teamB     = {
            vector4(-2221.316, -2333.808, 500.729, 183.404)
        },
        spectator = vector4(-2179.281, -2369.165, 525.729, 277.813)
    },

    {
        id        = 'neon4',
        name      = "NEON 4",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/Neon4.png',
        center    = vector3(-3197.236, -478.799, 318.881),
        radius    = 150.0,
        modes     = { '1v1', '2v2', '3v3' },
        weapons   = nil,
        teamA     = {
            vector4(-3242.604, -474.384, 318.881, 264.448)
        },
        teamB     = {
            vector4(-3166.541, -475.246, 318.881, 91.951)
        },
        spectator = vector4(-3197.236, -478.799, 343.881, 205.417)
    },

    {
        id        = 'skatepark',
        name      = "SKATEPARK",
        image     = 'https://r2.fivemanage.com/6v9KGi8lP3pI5FTEnO2P4/SkatePark.png',
        center    = vector3(-2595.843, -2218.091, 1271.626),
        radius    = 160.0,
        modes     = { '3v3', '4v4', '5v5' },
        weapons   = nil,
        teamA     = {
            vector4(-2614.650, -2278.546, 1267.654, 321.623)
        },
        teamB     = {
            vector4(-2567.187, -2181.128, 1271.643, 148.659)
        },
        spectator = vector4(-2595.843, -2218.091, 1296.626, 74.756)
    },
}

-- ساحة التدريب (باكت واحد، ما لها أي تأثير على الرانك)
Config.Training         = {
    enabled = true,                                 -- تشغيل التدريب
    bucket  = 90000,                                -- الباكت الي ينعزل فيه
    spawn   = vector4(1208.5, -3115.6, 5.5, 180.0), -- نقطة النزول
    loadout = 'training',                           -- السلاح من Config.Loadouts
    modes   = {                                     -- الأطوار: عدد الأهداف، والمسافة بينها، والوقت بالثواني
        aim      = { label = 'AIM TRAINING', targets = 12, spacing = 8.0, time = 120 },
        headshot = { label = 'HEADSHOT TRAINING', targets = 8, spacing = 12.0, time = 120 },
        range    = { label = 'FREE RANGE', targets = 0, spacing = 0.0, time = 0 }
    }
}

-- ============================================================================
-- ١٢أ. قيم البوتات  (للطاقم فقط)
-- ============================================================================
--
-- مبارزة تدريبية ضد بوتات، تبدأ من لوحة الإدارة. تشتغل بنفس عرض القيم
-- الحقيقية — باكت خاص، ونقاط نزول الماب، وراوندات، وهود، وكيل فيد، وشاشة
-- نهاية — عشان تقدر تجرّب طور أو ماب بشخص واحد.
--
-- وهي غير مصنّفة بقصد وما تنخلى مصنّفة. البوتات بيدز محليين على جهاز اللاعب
-- الي بدأها، لأن هذا المكان الوحيد الي يقدر ينشئ بيد ويعطيه ذكاء قتال، يعني
-- موتهم يبلّغ عنه ذاك الكلنت مو السيرفر يثبته. وما نبني شي على كلام الكلنت،
-- فقيم البوتات ما تعطي RP ولا MMR ولا إحصائيات ولا سجل قيم — ومحصورة على
-- الطاقم الي يملك الصلاحية تحت.
--
Config.BotMatch         = {
    enabled         = true, -- تشغيل قيم البوتات

    -- الصلاحية موجودة على أمر الإدارة نفسه، عشان يكون فيه مصدر واحد للحقيقة:
    -- Config.AdminActions.startBotMatch.permission ('pvp.admin.botmatch').
    -- والي يملك Config.Permissions.superAdmin كمان يعدّي طول ما
    -- Config.Permissions.adminGrantsAll مشغّل.

    -- أول باكت من المدى المستخدم لهذي الجلسات. كل قيم بوتات شغّالة تاخذ الي
    -- بعده (٦٤ باكت محجوزة من هنا) عشان إداريين يتدربون بنفس الوقت ما
    -- يتشاركون نفس العالم.
    bucket          = 90100,

    -- الماب: آيدي من Config.Maps، أو nil عشان الي بدأ يختار (اللوحة تعرض
    -- القائمة وترجع لأول ماب يدعم الطور).
    defaultMap      = nil,

    -- تركيبة الراوندات، مثل 1v1 العادي. عدد الراوندات المطلوبة للفوز تنحسب من
    -- عدد الراوندات نفسه، فما فيه إعداد ثاني يقدر يخالف الرقم المختار باللوحة.
    rounds          = 5, -- الافتراضي؛ اللوحة تعرض ١ و ٣ و ٥ و ٧ و ٩
    roundTime       = 120, -- بالثواني، و 0 يعني بلا حد
    countdown       = 5, -- تجميد قبل ما يبدأ الراوند
    roundEndDelay   = 5, -- وقفة على نتيجة الراوند قبل الي بعده
    endDelay        = 12, -- كم تضل شاشة النهاية قبل التنظيف

    -- جهة اللاعب الحقيقي
    loadout         = 'duel', -- سلاحه
    headshotOneShot = true,  -- نفس قاعدة الهيدشوت بطلقة وحدة مثل القيم الحقيقية

    -- سقف صارم. البوتات بيدز محليين، فالعدد الكبير يكلّف فريمات اللاعب الي
    -- بدأ وبس، ما يأثر على أحد ثاني.
    maxBots         = 5,

    bots            = {
        count = 1,                 -- الافتراضي، ويقدر يغيّره كل مرة لين maxBots
        model = 's_m_y_marine_01', -- شكل البوت
        namePrefix = 'BOT',        -- بادئة اسمه

        -- الجاهزيات الي تعرضها اللوحة. accuracy من ٠ إلى ١٠٠، و reaction
        -- معامل سرعة الإطلاق، و combatMovement صفر ثابت، ١ دفاعي، ٢ يتقدم،
        -- ٣ انتحاري.
        difficulties = {
            easy = {
                label = 'EASY',
                health = 150,
                armor = 0,
                accuracy = 15,
                reaction = 0.35,
                weapon = 'WEAPON_PISTOL',
                combatMovement = 1,
                alertness = 0
            },
            normal = {
                label = 'NORMAL',
                health = 200,
                armor = 0,
                accuracy = 35,
                reaction = 0.6,
                weapon = 'WEAPON_PISTOL_MK2',
                combatMovement = 2,
                alertness = 2
            },
            hard = {
                label = 'HARD',
                health = 200,
                armor = 0,
                accuracy = 60,
                reaction = 0.85,
                weapon = 'WEAPON_CARBINERIFLE',
                combatMovement = 2,
                alertness = 3
            },
            insane = {
                label = 'INSANE',
                health = 200,
                armor = 0,
                accuracy = 85,
                reaction = 1.0,
                weapon = 'WEAPON_CARBINERIFLE',
                combatMovement = 3,
                alertness = 3
            }
        },
        defaultDifficulty = 'normal' -- الجاهزية الافتراضية
    },

    -- يرسل النتيجة لويب هوك adminActions مثل أي أمر إداري ثاني
    logToWebhook    = true
}

-- ============================================================================
-- ١٣. تصويت الماب
-- ============================================================================

Config.MapVote          = {
    enabled     = true,     -- تشغيل التصويت
    options     = 3,        -- كم ماب ينعرض للتصويت
    duration    = 20,       -- بالثواني
    tieBreaker  = 'random', -- كيف ينحسم التعادل
    -- المابات الي لعبها هؤلاء اللاعبين بآخر N قيم تنزل أولويتها
    avoidRepeat = 2
}

-- ============================================================================
-- ١٤. الماتش ميكينق
-- ============================================================================

Config.Matchmaking      = {
    enabled             = true,

    tickInterval        = 2000, -- ملي ثانية بين كل دورة بحث

    -- توسيع نافذة البحث كل ما طال الانتظار
    mmrRangeStart       = 120, -- فرق MMR المسموح بالبداية
    mmrRangeStep        = 60, -- ينزاد كل expandInterval
    mmrRangeMax         = 1200, -- أقصى فرق MMR
    expandInterval      = 8000, -- ملي ثانية بين كل توسيع

    rankRangeStart      = 2, -- فرق أرقام الرانك بالبداية
    rankRangeStep       = 1, -- كم ينزاد كل توسيع
    rankRangeMax        = 12, -- أقصى فرق رانك

    -- تفضيل البنق (0 يطفيه)
    maxPing             = 200, -- البنق المفضّل
    pingRangeMax        = 350, -- أقصى بنق مقبول بعد التوسيع
    pingRelaxAfter      = 30000, -- بعد كم ملي ثانية يتساهل بالبنق

    -- تأكيد الجاهزية
    readyCheck          = {
        enabled         = true, -- تشغيل شاشة القبول
        duration        = 15, -- ثواني للقبول
        -- اللاعب ينحط بانتظار إذا ما قبل
        declineCooldown = 120,
        -- الي قبلوا يرجعون للطابور تلقائياً بأولوية
        requeueOnFail   = true
    },

    -- قيود القروب
    maxPartyRankGap     = 5,    -- فرق رقم الرانك المسموح داخل القروب
    partyRankGapEnabled = true, -- تشغيل القيد

    -- قيود الطابور
    minPlayersToStart   = nil, -- خلّها nil عشان تنحسب من الطور
    maxQueueTime        = 600, -- ثواني قبل ما ينشال اللاعب من الطابور

    -- قائمة التجنّب: اللاعبين الي تجنّبتهم قريب ما ينحطون معك
    avoidListSize       = 5,  -- كم واحد تقدر تتجنّب
    avoidDuration       = 3600, -- بالثواني

    -- تعويض اللاعبين الي طلعوا قبل ما تبدأ القيم
    allowBackfill       = true,
    backfillWindow      = 45 -- ثواني بعد بداية القيم
}

-- ============================================================================
-- ١٥. مسار القيم
-- ============================================================================

-- ============================================================================
-- ١٥ب. صور اللاعبين  (هود القيم والسكور بورد)
-- ============================================================================
--
-- كل لاعب بالهود وبسكور بورد التاب يطلع له صورة. من وين تجي الصورة راجع لك.
--
Config.Avatars          = {
    enabled = true, -- تشغيل الصور

    -- تطلع كل ما ما قدرنا نجيب صورة حقيقية. استخدم ملف محلي تحت Files/ui/img/
    -- (وسجّله بقائمة `files` بملف fxmanifest.lua) أو أي رابط.
    default = 'https://cdn.discordapp.com/embed/avatars/0.png',

    -- كيف نجيب الصورة. أول طريقة تنجح هي المستخدمة، وكل خطوة تقدر تطفيها.
    --
    --   'discord'  نسأل ديسكورد عن صورة حساب اللاعب المربوط.
    --              يحتاج توكن بوت؛ شوف تحت.
    --   'template' تبني الرابط بنفسك من آيدي ديسكورد اللاعب، بدون أي طلب
    --              للـ API. الـ %s ينبدل بآيدي الديسكورد المجرّد.
    --   'none'     يستخدم `default` دايم.
    --
    source = 'discord',

    -- ما تنستخدم إلا إذا كان المصدر 'template'
    template = 'https://my-cdn.example.com/avatars/%s.png',

    discord = {
        -- توكن بوت من https://discord.com/developers/applications.
        -- البوت ما يحتاج أي صلاحية ولا يحتاج يكون بسيرفرك — قراءة صورة
        -- المستخدم العامة تحتاج التوكن نفسه بس.
        --
        -- خلّه فاضي والنظام يرجع لـ `default` بهدوء بدون أخطاء.
        -- ولا تحط التوكن بأي مكان يوصل للكلنت؛ هذا الملف سيرفر فقط، وعشان كذا
        -- هو موجود هنا.
        botToken = '',

        -- ديسكورد يحد الطلبات بقوة، فالنتائج تنحفظ بكاش. بالثواني.
        cacheTime = 21600, -- ٦ ساعات

        -- حجم الصورة المطلوبة (من مضاعفات ٢، بين ١٦ و ٤٠٩٦)
        size = 128
    }
}

-- ============================================================================
-- ١٥ج. أسماء الفرق  (هود القيم والسكور بورد)
-- ============================================================================
--
Config.TeamNames        = {
    -- 'fixed'  الاسمين تحت، دايم
    -- 'leader' يسمي كل جهة باسم واحد من لاعبيها، مثال "M547'S TEAM".
    --          وبـ 1v1 هذا يعني اسم اللاعبين مقابل بعض، وغالباً هذا الي تبيه.
    mode = 'leader',

    fixed = { [1] = 'TEAM A', [2] = 'TEAM B' }, -- الأسماء الثابتة

    -- تنستخدم مع 'leader'. الـ %s هو اسم اللاعب.
    pattern = "%s'S TEAM",

    -- مع 'leader'، الفريق الي فيه لاعب واحد يطلع باسمه بس بدون الصيغة.
    soloIsPlain = true,

    -- مين يسمّي الفريق: 'party' ياخذ قائد القروب إذا الجهة دخلت مع بعض، وإلا
    -- ياخذ أعلى لاعب رانك.
    pick = 'party'
}

Config.Match            = {
    -- النبضة العامة الي تشتغل عليها آلة حالة القيم
    tickInterval         = 250,

    warmupTime           = 10, -- ثواني بعد النقل قبل أول راوند
    roundStartFreeze     = 3, -- العد التنازلي ٣-٢-١-انطلق
    roundEndTime         = 6, -- ثواني تنعرض بعد كل راوند
    matchEndTime         = 15, -- مدة شاشة النتيجة وأفضل لاعب
    cleanupTime          = 5, -- ثواني التنظيف بعدها

    -- يرجّع اللاعب لمكانه بنفس اللحظة الي تنتهي فيها القيم، بدون ما ينتظر
    -- شاشة النتيجة تخلص. الشاشة تضل قدامه وهو راجع — يقرأها بمكانه.
    -- خلّه false إذا تبي اللاعب يقعد بالساحة لين تخلص شاشة النتيجة (السلوك
    -- القديم: ينتظر matchEndTime كامل قبل ما يترجّع).
    returnImmediately    = true,

    spawnProtection      = 3, -- ثواني حماية بعد النزول
    antiSpawnKill        = true,
    antiSpawnKillRadius  = 12.0,

    -- الخروج من الزون
    boundary             = {
        warningTime = 5,       -- ثواني قبل العقوبة
        action      = 'kill'   -- العقوبة: 'kill' قتل أو 'teleport' نقل
    },

    -- تصويت الانسحاب
    surrender            = {
        enabled       = true, -- تشغيل التصويت
        minRound      = 5,    -- من أي راوند يصير مسموح
        requiredRatio = 0.75, -- نسبة الفريق الي لازم توافق
        voteDuration  = 30,   -- مدة التصويت بالثواني
        cooldown      = 120   -- ثواني قبل تصويت جديد
    },

    -- الوقت الإضافي
    overtime             = {
        enabled       = true, -- تشغيل الوقت الإضافي
        roundsPerHalf = 2,    -- راوندات كل شوط إضافي
        winBy         = 2,    -- لازم تفوز بفرق كم راوند
        maxOvertimes  = 5,    -- أكثر عدد أشواط إضافية
        suddenDeath   = true  -- آخر شوط إضافي يكون راوند واحد حاسم
    },

    -- شروط إلغاء القيم
    minPlayersToContinue = 1,  -- لكل فريق، تحت هذا الرقم تنحسب خسارة
    abandonForfeitDelay  = 60, -- ثواني يقدر الفريق يلعب فيها ناقص

    -- سقف مدة القيم
    maxMatchDuration     = 5400 -- إيقاف إجباري (بالثواني)
}

-- ============================================================================
-- ١٥د. الكوما (vRP)
-- ============================================================================
--
-- الـ vRP ما يخلي اللاعب يموت: ينزل دمه لحد معيّن ويدخله كوما. الكلنت يمسكها
-- على طول من الدم (شوف Config.Coma بكونفق الكلنت)، وهذا سريع ومجاني لكنه
-- يعتمد على إن الرقم المكتوب بالكونفق هو نفس الرقم الي يستخدمه الـ vRP حقك.
--
-- هنا نسأل الـ vRP نفسه بدل ما نخمّن: الدالة vRP.isInComa تعطي الجواب المعتمد.
-- فالكلنت يمسكها فوراً، والسيرفر يمسك أي حالة فاتت على الكلنت — مثلاً لو
-- الـ vRP حقك يوقف اللاعب على رقم غير المكتوب بالكونفق.

Config.ComaWatch = {
    -- خلّه false إذا نسخة vRP حقك ما فيها isInComa، أو ما تبي هذا الفحص أصلاً.
    -- (السكربت يفحص وجود الدالة لحاله، فلو ما كانت موجودة يطفي نفسه ويكتب
    --  سطر بالكونسول — ما ينكسر شي.)
    enabled = true,

    -- كل كم ملي ثانية ينفحص اللاعبين الأحياء داخل الراوندات الشغّالة.
    -- الفحص استدعاء داخلي للـ vRP مو استعلام قاعدة بيانات، فهو رخيص، لكن ما
    -- فيه داعي يصير كل تكة. الكلنت أصلاً يمسكها فوراً، وهذا شبكة أمان.
    interval = 2000
}

-- ============================================================================
-- ١٦. باكتات العزل
-- ============================================================================

Config.Buckets          = {
    start             = 10000, -- أول رقم باكت ينعطى لقيم
    max               = 89999, -- آخر رقم
    lockdownMode      = 'strict', -- قفل الكيانات داخل باكتات القيم
    populationEnabled = false, -- بدون مواطنين وسيارات داخل القيم
    -- الباكتات المحجوزة للغرف الخاصة
    customStart       = 60000,
    customMax         = 79999,
    -- الباكت المستخدم بمرحلة اللوبي وتصويت الماب
    lobby             = 95000
}

-- ============================================================================
-- ١٧. الرجوع بعد الانقطاع
-- ============================================================================

Config.Reconnect        = {
    enabled       = true,    -- تشغيل الرجوع
    window        = 180,     -- ثواني عنده يرجع فيها
    restoreState  = true,    -- ترجيع الدم والدرع والسلاح والنتيجة
    -- الرجوع داخل المهلة يلغي عقوبة الخروج
    cancelPenalty = true,
    -- توقيف القيم وهي تنتظره (الراوندات ما تمشي)
    pauseMatch    = false,
    maxReconnects = 2    -- كم مرة يقدر يرجع بنفس القيم
}

-- ============================================================================
-- ١٨. الخمول
-- ============================================================================

Config.AFK              = {
    enabled            = true, -- تشغيل نظام الخمول
    checkInterval      = 5000, -- ملي ثانية بين كل فحص
    warningAfter       = 45, -- ثواني بدون حركة قبل التحذير
    kickAfter          = 75, -- ثواني بدون حركة قبل الطرد
    -- إشارات النشاط
    signals            = {
        movement    = true,   -- المشي
        camera      = true,   -- تحريك الكاميرا
        shooting    = true,   -- الإطلاق
        interaction = true    -- التفاعل
    },
    cameraDeltaDegrees = 4.0, -- كم درجة تحرّك كاميرا تنحسب نشاط
    movementDistance   = 1.5, -- كم متر حركة تنحسب نشاط

    -- ما ينحسب خمول أبداً بهذي الحالات
    ignoreStates       = { 'WAITING', 'READY', 'MAP_VOTE', 'STARTING', 'ROUND_END', 'MATCH_END', 'CLEANUP' },
    ignoreSpectators   = true, -- المشاهدين ما ينحسبون

    penalty            = {
        removeFromMatch = true, -- يطلع من القيم
        rpPenalty       = 25,   -- كم RP ينخصم
        cooldown        = 600,  -- ثواني قبل ما يقدر يبحث من جديد
        countsAsLeave   = true  -- تنحسب مثل الخروج من القيم
    }
}

-- ============================================================================
-- ١٩. عقوبة الخروج من القيم
-- ============================================================================

Config.LeavePenalty     = {
    enabled           = true, -- تشغيل العقوبات

    -- المدة الي تنعد فيها المخالفات
    windowDays        = 7,

    tiers             = { -- درجات العقوبة: رقم المخالفة، الخصم، الانتظار، الحظر بالثواني
        { offence = 1, rp = 10, cooldown = 0,    ban = 0,      label = 'Warning' },
        { offence = 2, rp = 20, cooldown = 300,  ban = 0,      label = 'Short Cooldown' },
        { offence = 3, rp = 35, cooldown = 1800, ban = 0,      label = 'Long Cooldown' },
        { offence = 4, rp = 50, cooldown = 0,    ban = 86400,  label = 'Ranked Ban 24h' },
        { offence = 5, rp = 60, cooldown = 0,    ban = 604800, label = 'Ranked Ban 7d' }
    },

    -- الخروج قبل ما تبدأ القيم فعلياً يكلّف أقل
    preLiveMultiplier = 0.4,

    -- تسامح: الانقطاع الي يرجع بالوقت ما ينحسب مخالفة
    graceOnReconnect  = true
}

-- ============================================================================
-- ٢٠. الحظر من الرانكد
-- ============================================================================

Config.RankBan          = {
    types           = { 'RANKED', 'MODE', 'CUSTOM', 'CHAT', 'PARTY', 'PERMANENT' }, -- أنواع الحظر

    presetDurations = {                                                   -- المدد الجاهزة باللوحة
        { label = '1 Hour',    seconds = 3600 },
        { label = '6 Hours',   seconds = 21600 },
        { label = '24 Hours',  seconds = 86400 },
        { label = '3 Days',    seconds = 259200 },
        { label = '7 Days',    seconds = 604800 },
        { label = '30 Days',   seconds = 2592000 },
        { label = 'Permanent', seconds = 0 }
    },

    requireReason   = true, -- السبب إجباري
    requireEvidence = false, -- الدليل إجباري
    notifyPlayer    = true  -- يبلّغ اللاعب بالحظر
}

-- ============================================================================
-- ٢١. مكافحة رفع الرانك بالغش (تبويست)
-- ============================================================================
-- ما فيه شي هنا يحظر تلقائياً. الكشف يرفع بلاغ مع الأدلة عشان الطاقم يراجعه.

Config.AntiBoost        = {
    enabled = true, -- تشغيل المكافحة

    -- يحلل آخر N قيم للاعب
    sampleSize = 25,

    detectors = {            -- الكواشف: severity هي درجة الخطورة
        repeatedOpponent = { -- نفس الخصم يتكرر
            enabled   = true,
            threshold = 6,   -- نفس الخصم بـ N قيم من العيّنة
            severity  = 2
        },
        repeatedVictim = {  -- نفس الضحية تتكرر
            enabled   = true,
            threshold = 25, -- قتل نفس اللاعب N مرة داخل العيّنة
            severity  = 2
        },
        shortMatches = {      -- قيمات قصيرة بشكل مريب
            enabled     = true,
            minDuration = 90, -- بالثواني
            threshold   = 5,  -- N قيمة قصيرة مشبوهة
            severity    = 2
        },
        intentionalLoss = {       -- خسارة متعمدة
            enabled   = true,
            maxKD     = 0.15,     -- نسبة قتل/موت منخفضة بشكل مريب
            minDeaths = 10,       -- أقل عدد موتات عشان تنحسب
            threshold = 3,
            severity  = 3
        },
        winTrading = {     -- تبادل الفوز
            enabled   = true,
            threshold = 4, -- فوز متبادل مع نفس الخصم
            severity  = 3
        },
        altAccount = {                -- حساب ثاني لنفس الشخص
            enabled        = true,
            matchOnLicense = false,   -- نفس عائلة الرخصة
            matchOnIP      = true,    -- نفس الآيبي
            newAccountDays = 3,       -- الحساب أجد من كم يوم
            severity       = 3
        },
        abnormalRP = {       -- RP يزيد بسرعة غير طبيعية
            enabled   = true,
            rpPerHour = 260, -- أكثر RP بالساعة يعتبر طبيعي
            severity  = 2
        },
        impossibleHeadshot = {    -- نسبة هيدشوت مستحيلة
            enabled       = true,
            headshotRatio = 0.85, -- نسبة القتلات الي بالرأس
            minKills      = 25,   -- أقل عدد قتلات عشان تنحسب
            severity      = 3
        },
        linkedMatches = {  -- نفس اللوبي يتكرر
            enabled   = true,
            threshold = 5, -- نفس تركيبة اللوبي تكررت N مرة
            severity  = 2
        }
    },

    -- البلاغات الي مجموع خطورتها من هذا الرقم فوق تنعلّم للإداريين
    reviewThreshold = 5,

    -- متى يشتغل المحلل (لكل لاعب، بعد نهاية القيم)
    analyseOnMatchEnd = true,
    -- كم يوم تنحفظ صفوف الأدلة الخام
    evidenceRetentionDays = 30
}

-- ============================================================================
-- ٢٢. المواسم
-- ============================================================================

Config.Seasons          = {
    enabled             = true, -- تشغيل نظام المواسم

    -- ينشئ موسم تلقائياً إذا ما فيه موسم شغّال
    autoCreate          = true,
    defaultDurationDays = 60,  -- مدة الموسم بالأيام
    namePattern         = 'Season %d', -- صيغة اسم الموسم

    -- الي يصير بنهاية الموسم
    reset               = {
        mode           = 'soft', -- 'soft' جزئي أو 'hard' كامل أو 'none' بدون
        -- معادلة التصفير الجزئي: الـ RP الجديد = floor(القديم × factor) + offset
        softFactor     = 0.55,  -- المعامل
        softOffset     = 120,   -- الزيادة الثابتة
        keepMMR        = true,  -- يبقي الـ MMR
        mmrSoftFactor  = 0.85,  -- معامل تخفيض الـ MMR
        resetPlacement = true   -- يرجّع مباريات التحديد
    },

    -- يأرشف لوحة الصدارة ويوزع الجوائز بنهاية الموسم
    archiveLeaderboard  = true,
    distributeRewards   = true,

    -- كل كم ملي ثانية ينفحص انتهاء الموسم
    checkInterval       = 60000,

    -- الموسم ما ينتهي وفيه قيمات شغّالة؛ ينتظرها تخلص.
    waitForLiveMatches  = true
}

-- ============================================================================
-- ٢٣. الجوائز
-- ============================================================================
-- النوع: 'money' فلوس أو 'item' غرض أو 'weapon' سلاح أو 'vehicle' سيارة أو
--        'group' قروب أو 'title' لقب أو 'badge' شارة أو 'frame' إطار أو
--        'effect' مؤثر

-- ============================================================================
-- ١٦ب. المتجر — البطايق والألقاب الي تنشترى بالكوينز
-- ============================================================================
--
-- شكليات بس، وما لها أي تأثير على اللعب أبداً:
--   البطايق (cards)   الخلفية خلف مربع اللاعب باللوبي
--   الألقاب (titles)  كلمة تطلع جنب اسمه
--
-- الكوينز يعطيها الطاقم (لوحة الإدارة > POINTS > Give Coins)، وكمان تجي من
-- جوائز القيم تحت إذا شغّلت `earnPerMatch`. الأسعار والملكية كلها تنحسم
-- بالسيرفر؛ الكلنت ما يسوي إلا يطلب الشراء.
--
Config.Store            = {
    enabled = true, -- تشغيل المتجر

    currency = {
        label    = 'COINS', -- اسم العملة بالواجهة
        starting = 0,       -- رصيد الحساب الجديد
        max      = 10000000 -- أقصى رصيد
    },

    -- حط رقم إذا تبي الكوينز تنعطى كمان على كل قيم. الصفر يعني الطاقم بس.
    earnPerMatch = { win = 0, loss = 0, mvp = 0 },

    -- ألوان شارة الندرة الصغيرة على كل غرض
    rarities = {
        common    = { label = 'COMMON', color = '#8B93A3' },
        rare      = { label = 'RARE', color = '#3FA9FF' },
        epic      = { label = 'EPIC', color = '#C158FF' },
        legendary = { label = 'LEGENDARY', color = '#F5C542' }
    },

    -- ---- البطايق -------------------------------------------------------
    -- الحقل `image` يقبل أي رابط، أو ملف تحطه تحت Files/ui/img/ (سجّله بقائمة
    -- `files` بملف fxmanifest.lua واكتبه 'img/name.png').
    -- البطاقة المعلّمة افتراضية يملكها الكل وما تنباع.
    cards = {
        { id = 'default',     name = 'Default',           rarity = 'common',    price = 0,    image = '',                                                                                            default = true },
        { id = 'black_thorn', name = 'Black Thorn',       rarity = 'rare',      price = 200,  image = 'https://images.unsplash.com/photo-1511497584788-876760111969?auto=format&fit=crop&w=600&q=85' },
        { id = 'bucket',      name = 'Bucket of Trouble', rarity = 'rare',      price = 300,  image = 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=600&q=85' },
        { id = 'bracelet',    name = 'The Bracelet',      rarity = 'rare',      price = 400,  image = 'https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=600&q=85' },
        { id = 'wayfinder',   name = 'Way Finder',        rarity = 'epic',      price = 500,  image = 'https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=600&q=85' },
        { id = 'op',          name = 'Op',                rarity = 'epic',      price = 750,  image = 'https://images.unsplash.com/photo-1519608487953-e999c86e7455?auto=format&fit=crop&w=600&q=85' },
        { id = 'insidious',   name = 'Insidious',         rarity = 'legendary', price = 1000, image = 'https://images.unsplash.com/photo-1534447677768-be436bb09401?auto=format&fit=crop&w=600&q=85' },
        { id = 'infinity',    name = 'Infinity',          rarity = 'legendary', price = 1500, image = 'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&fit=crop&w=600&q=85' },

        -- Animated Cards
        { id = 'phoenix',     name = 'Phoenix',           rarity = 'legendary', price = 1700, image = 'https://raw.githubusercontent.com/m547X/RankCards/main/phonix.gif' },
        { id = 'dragon',      name = 'Dragon',            rarity = 'legendary', price = 2000, image = 'https://raw.githubusercontent.com/m547X/RankCards/main/dragon.gif' },
        { id = 'skull',       name = 'Skull',             rarity = 'legendary', price = 2300, image = 'https://raw.githubusercontent.com/m547X/RankCards/main/skull.gif' },
        { id = 'shadow',      name = 'Shadow',            rarity = 'legendary', price = 2600, image = 'https://raw.githubusercontent.com/m547X/RankCards/main/Shadow.gif' },
        { id = 'demon',       name = 'Demon',             rarity = 'legendary', price = 3000, image = 'https://raw.githubusercontent.com/m547X/RankCards/main/Demon.gif' },
        { id = 'hunter',      name = 'Hunter',            rarity = 'legendary', price = 3400, image = 'https://raw.githubusercontent.com/m547X/RankCards/main/hunter.gif' },
        { id = 'gojo',        name = 'Gojo',              rarity = 'legendary', price = 3800, image = 'https://raw.githubusercontent.com/m547X/RankCards/main/gojo.gif' },
    },

    -- ---- الألقاب -------------------------------------------------------
    -- الحقل `color` يلوّن اللقب بكل مكان يطلع فيه الاسم.
    titles = {
        { id = 'none', name = '—', rarity = 'common', price = 0, default = true },
        { id = 'rookie', name = 'ROOKIE', rarity = 'common', price = 0, color = '#B9C1CC' },
        { id = 'sharpshooter', name = 'SHARPSHOOTER', rarity = 'rare', price = 300, color = '#3FA9FF' },
        { id = 'demon', name = 'DEMON', rarity = 'epic', price = 800, color = '#C158FF' },
        { id = 'legend', name = 'LEGEND', rarity = 'legendary', price = 2000, color = '#F5C542' }
    },

    -- ---- المؤثرات ------------------------------------------------------
    -- حركة تشتغل فوق البطاقة داخل القروب. كلها ترسمها الواجهة نفسها — بدون
    -- صور وبدون ملفات تحتاج ترفعها.
    --
    --   anim   أي حركة تشتغل. وحدة من:
    --            glow    هالة حول البطاقة، تتنفس
    --            scan    شريط ضوء ينزل من فوق لتحت
    --            embers  جمرات طالعة لفوق
    --            holo    لمعة تعبر بالقطر
    --            storm   وميض غير منتظم على البطاقة كلها
    --            aurora  موجة ألوان بطيئة تعبر
    --            sparkle نقاط ضوء تلمع بمكانها
    --            rain    خطوط تنزل مثل المطر
    --            pulse   حلقات تتوسع من الحواف
    --            flames  نار تطلع من تحت
    --            orbit   ضوء يلف حول الإطار
    --   color  اللون. والـ color2 تستخدمه الحركات الي تمزج لونين.
    --   speed  السرعة، و 1.0 هي السرعة المصممة، و 0.5 نصفها، و 2.0 ضعفها.
    --
    -- الـ `id` مجرد اسم للسطر، فتقدر تبيع نفس الحركة كم مرة ما تبي بألوان
    -- وسرعات مختلفة. انسخ السطر، وغيّر الآيدي واللون والسعر.
    effects = {
        { id = 'none', name = '—', rarity = 'common', price = 0, default = true },
        { id = 'glow', name = 'Aura', rarity = 'common', price = 250, anim = 'glow', color = '#3FA9FF' },
        { id = 'sparkle', name = 'Stardust', rarity = 'common', price = 350, anim = 'sparkle', color = '#EAF1F8' },
        { id = 'scan', name = 'Scanline', rarity = 'rare', price = 500, anim = 'scan', color = '#2FDD9B' },
        { id = 'embers', name = 'Embers', rarity = 'rare', price = 650, anim = 'embers', color = '#FF7A3C' },
        { id = 'rain', name = 'Downpour', rarity = 'rare', price = 700, anim = 'rain', color = '#6FB8FF' },
        { id = 'pulse', name = 'Pulse', rarity = 'rare', price = 750, anim = 'pulse', color = '#2FDD9B' },
        { id = 'holo', name = 'Hologram', rarity = 'epic', price = 1100, anim = 'holo', color = '#C158FF' },
        { id = 'aurora', name = 'Aurora', rarity = 'epic', price = 1400, anim = 'aurora', color = '#2FDD9B', color2 = '#C158FF' },
        { id = 'orbit', name = 'Orbit', rarity = 'epic', price = 1600, anim = 'orbit', color = '#3FA9FF' },
        { id = 'flames', name = 'Inferno', rarity = 'legendary', price = 2000, anim = 'flames', color = '#FF7A3C', color2 = '#FFD24A' },
        { id = 'storm', name = 'Storm', rarity = 'legendary', price = 2200, anim = 'storm', color = '#F5C542' }
    },

    -- ---- الإطارات وزخارف الأفتار ---------------------------------------
    -- خانتين منفصلات، كل وحدة تنشترى وتنلبس لحالها:
    --
    --   frames   الإطار حول بطاقة اللاعب كاملة
    --   avatars  الزخرفة حول الصورة الشخصية، زي ما يحط الديسكورد زخرفة حول
    --            الأفتار
    --
    -- الاثنتين تشتركون بكل الحقول تحت، لأنها نفس الوصفة بس مرسومة بمكانين.
    -- والاثنتين تنبنون من هذي الأرقام مو من قائمة ثابتة، فتقدر تسوي أشكالك
    -- بدون ما تلمس أي كود.
    --
    --   style   كيف ينرسم الخط:
    --             solid     خط واحد
    --             double    خط، ثم فراغ، ثم خط ثاني
    --             dashed    خط متقطع
    --             dots      صف نقاط حول الحافة
    --             gradient  الخط يتدرج من color إلى color2 ثم يرجع
    --             corners   الزوايا الأربع بس
    --             studs     مكعب صغير بكل زاوية
    --             ticks     خط رفيع مع علامة أطول بكل زاوية
    --             ribbon    شريط عرضي فوق
    --             spin      حلقة لون تلف حوله
    --             halo      هالة ناعمة تنتشر برا، بدون حافة حادة
    --             bare      بدون أي خط — إذا تبيه رسمة بس، شوف `art` تحت
    --
    --           الصورة الشخصية دايرة، فأي شكل مكانه زوايا المربع ينرسم كقوس
    --           بـ `avatars`: الـ corners والـ ticks تصير علامات حول الحافة،
    --           والـ studs تصير مسامير عليها، والـ ribbon ينحني فوق الرأس.
    --
    --   art     رسمة تنلبس فوق الخط — وهذي هي الي تخلي الشكل يشبه زخارف
    --           الديسكورد بدل ما يكون مجرد إطار. تاخذ ألوانها من نفس السطر،
    --           فرسمة وحدة تخدم أي عدد صفوف.
    --
    --             بـ `avatars`، الرسمة كلها تلف حول الصورة:
    --               orbs      أضواء طايرة حولها
    --               vines     غصن شوكي يتسلق حولها
    --               crystals  شظايا طالعة من الحافة
    --               flames    نار تلعب حولها
    --               wings     جناحين
    --               laurel    إكليل غار، مفتوح من فوق
    --               tech      عدّة تصويب: أقواس وعلامات وشريحة
    --
    --             وبـ `frames`، رشة بكل زاوية من الزوايا الأربع:
    --               vines     غصن ورد يتسلق للداخل
    --               crystals  عنقود شظايا
    --               flames    نار تزحف على الحواف
    --               tech      قوس صلب مع علامات وشريحة
    --               stars     لمعات متناثرة
    --
    --           الاسم الي ما له رسمة بتلك الجهة ينتجاهل بهدوء، فالإطار الي
    --           يطلب 'wings' يضل بإطاره وما يزيد عليه شي.
    --
    --           وزخرفة الأفتار تقدر تأشّر على صورتك أنت بدل الرسمات: حط الملف
    --           بـ Files/ui/img واكتب اسمه، مثال art = 'img/deco.png'. أي شي
    --           فيه نقطة أو سلاش ينقرأ كملف. والصورة ما ترسم إلا حول الصورة
    --           الشخصية — الصورة الوحدة ما تنقلب أربع زوايا وتضل شكلها حلو —
    --           وتحتفظ بألوانها هي، فصورة APNG مسحوبة من باكج زخارف تنزل زي ما
    --           هي مرسومة.
    --
    --   width   السماكة بالبكسل (من ١ إلى ٦ تطلع حلوة)
    --   color   اللون الأساسي
    --   color2  الطرف الثاني للتدرج أو الدوران أو الهالة. إذا ما كتبته يصير
    --           اللون الثاني هو نفس الأول.
    --   glow    كم ينتشر التوهج برا، بالبكسل. صفر أو بدون كتابة يعني مسطّح.
    --   animated  تدرج يتحرك ويلف. ما له معنى إلا مع style = 'gradient'؛
    --           الـ spin والـ halo يتحركون دايم.
    --   speed   ثواني اللفة الكاملة. الافتراضي ٦.
    --
    -- الـ `id` مجرد اسم للسطر، والقائمتين منفصلات، فنفس الآيدي يقدر يطلع
    -- بالاثنتين — وهذي هي طريقة بيع الطقم المتناسق. انسخ السطر، وغيّر الآيدي
    -- والألوان، وصار عندك غرض جديد بالمتجر.
    frames = {
        { id = 'none', name = '—', rarity = 'common', price = 0, default = true },

        -- ---- الخطوط ----
        {
            id = 'steel',
            name = 'Steel',
            rarity = 'common',
            price = 200,
            style = 'double',
            width = 2,
            color = '#8B93A3'
        },
        {
            id = 'dash',
            name = 'Marker',
            rarity = 'common',
            price = 250,
            style = 'dashed',
            width = 2,
            color = '#6FB8FF'
        },
        {
            id = 'beads',
            name = 'Beads',
            rarity = 'common',
            price = 300,
            style = 'dots',
            width = 3,
            color = '#B9C1CC'
        },
        {
            id = 'corners',
            name = 'Bracket',
            rarity = 'rare',
            price = 450,
            style = 'corners',
            width = 3,
            color = '#2FDD9B',
            glow = 14
        },
        {
            id = 'studs',
            name = 'Rivets',
            rarity = 'rare',
            price = 500,
            style = 'studs',
            width = 3,
            color = '#F5C542',
            glow = 12
        },
        {
            id = 'gold',
            name = 'Gold',
            rarity = 'rare',
            price = 600,
            style = 'solid',
            width = 2,
            color = '#F5C542',
            glow = 22
        },
        {
            id = 'ticks',
            name = 'Precision',
            rarity = 'rare',
            price = 650,
            style = 'ticks',
            width = 2,
            color = '#3FA9FF',
            glow = 12
        },
        {
            id = 'crimson',
            name = 'Crimson',
            rarity = 'rare',
            price = 700,
            style = 'solid',
            width = 3,
            color = '#FF3B4E',
            glow = 24
        },
        {
            id = 'banner',
            name = 'Banner',
            rarity = 'epic',
            price = 900,
            style = 'ribbon',
            width = 4,
            color = '#C158FF',
            color2 = '#3FA9FF',
            glow = 16
        },
        {
            id = 'neon',
            name = 'Neon',
            rarity = 'epic',
            price = 1200,
            style = 'gradient',
            width = 2,
            color = '#3FA9FF',
            color2 = '#C158FF',
            animated = true
        },
        {
            id = 'toxic',
            name = 'Toxic',
            rarity = 'epic',
            price = 1400,
            style = 'gradient',
            width = 3,
            color = '#2FDD9B',
            color2 = '#C7FF3F',
            animated = true,
            glow = 18
        },
        {
            id = 'void',
            name = 'Void',
            rarity = 'epic',
            price = 1800,
            style = 'spin',
            width = 3,
            color = '#C158FF',
            color2 = '#3FA9FF',
            speed = 5,
            glow = 18
        },
        {
            id = 'solar',
            name = 'Solar',
            rarity = 'epic',
            price = 1900,
            style = 'halo',
            width = 4,
            color = '#FFD24A',
            color2 = '#FF4757',
            glow = 24
        },
        {
            id = 'royal',
            name = 'Royal',
            rarity = 'legendary',
            price = 2500,
            style = 'gradient',
            width = 3,
            color = '#F5C542',
            color2 = '#FF4757',
            animated = true,
            glow = 20
        },
        {
            id = 'prism',
            name = 'Prism',
            rarity = 'legendary',
            price = 3000,
            style = 'gradient',
            width = 3,
            color = '#3FA9FF',
            color2 = '#FF7A3C',
            animated = true,
            glow = 26,
            speed = 3
        },

        -- ---- رسمات بزوايا البطاقة ----
        {
            id = 'uplink',
            name = 'Uplink',
            rarity = 'rare',
            price = 1100,
            style = 'ticks',
            art = 'tech',
            width = 2,
            color = '#2FDD9B',
            color2 = '#EAF1F8',
            glow = 10
        },
        {
            id = 'starlit',
            name = 'Starlit',
            rarity = 'rare',
            price = 1200,
            style = 'bare',
            art = 'stars',
            color = '#EAF1F8',
            color2 = '#6FB8FF',
            glow = 12
        },
        {
            id = 'roses',
            name = 'Dark Roses',
            rarity = 'epic',
            price = 2000,
            style = 'solid',
            art = 'vines',
            width = 2,
            color = '#C158FF',
            color2 = '#7A3FCF',
            glow = 14
        },
        {
            id = 'geode',
            name = 'Geode',
            rarity = 'epic',
            price = 2100,
            style = 'bare',
            art = 'crystals',
            color = '#3FA9FF',
            color2 = '#8FE3FF',
            glow = 12
        },
        {
            id = 'ashfall',
            name = 'Ashfall',
            rarity = 'epic',
            price = 2300,
            style = 'solid',
            art = 'flames',
            width = 2,
            color = '#FF4757',
            color2 = '#FFD24A',
            glow = 16
        },
        {
            id = 'briar',
            name = 'Briar',
            rarity = 'legendary',
            price = 3200,
            style = 'solid',
            art = 'vines',
            width = 2,
            color = '#C158FF',
            color2 = '#2FDD9B',
            glow = 18
        },
        {
            id = 'forge',
            name = 'Forge',
            rarity = 'legendary',
            price = 3400,
            style = 'gradient',
            art = 'flames',
            width = 3,
            color = '#FF7A3C',
            color2 = '#FFD24A',
            animated = true,
            glow = 22
        }
    },

    -- الزخرفة حول الصورة الشخصية. نفس حقول الإطار؛ والآيديهات المشتركة مع
    -- القائمة فوق هي النصف المطابق من نفس الطقم.
    avatars = {
        { id = 'none', name = '—', rarity = 'common', price = 0, default = true },

        -- ---- الحلقات ----
        {
            id = 'ring',
            name = 'Ring',
            rarity = 'common',
            price = 300,
            style = 'double',
            width = 2,
            color = '#6FB8FF'
        },
        {
            id = 'bolts',
            name = 'Bolts',
            rarity = 'rare',
            price = 550,
            style = 'studs',
            width = 3,
            color = '#F5C542',
            glow = 12
        },
        {
            id = 'halo',
            name = 'Halo',
            rarity = 'rare',
            price = 800,
            style = 'halo',
            width = 3,
            color = '#F5C542',
            color2 = '#FF7A3C'
        },
        {
            id = 'vortex',
            name = 'Vortex',
            rarity = 'epic',
            price = 1500,
            style = 'spin',
            width = 3,
            color = '#3FA9FF',
            color2 = '#C158FF',
            speed = 4
        },
        {
            id = 'cinder',
            name = 'Cinder',
            rarity = 'epic',
            price = 1700,
            style = 'spin',
            width = 4,
            color = '#FF7A3C',
            color2 = '#FFD24A',
            speed = 3
        },

        -- ---- رسمات تنلبس حول الصورة ----
        {
            id = 'wisps',
            name = 'Wisps',
            rarity = 'rare',
            price = 900,
            style = 'bare',
            art = 'orbs',
            color = '#2FE6C8',
            color2 = '#7CFFE6',
            glow = 18,
            speed = 8
        },
        {
            id = 'thorns',
            name = 'Thorns',
            rarity = 'rare',
            price = 1000,
            style = 'solid',
            art = 'vines',
            width = 2,
            color = '#2FDD9B',
            color2 = '#C7FF3F',
            glow = 10
        },
        {
            id = 'shards',
            name = 'Shards',
            rarity = 'epic',
            price = 1600,
            style = 'bare',
            art = 'crystals',
            color = '#6FB8FF',
            color2 = '#C158FF',
            glow = 16
        },
        {
            id = 'pyre',
            name = 'Pyre',
            rarity = 'epic',
            price = 1800,
            style = 'solid',
            art = 'flames',
            width = 2,
            color = '#FF7A3C',
            color2 = '#FFD24A',
            glow = 20
        },
        {
            id = 'visor',
            name = 'Visor',
            rarity = 'epic',
            price = 1900,
            style = 'ticks',
            art = 'tech',
            width = 2,
            color = '#3FA9FF',
            color2 = '#EAF1F8',
            glow = 14
        },
        {
            id = 'seraph',
            name = 'Seraph',
            rarity = 'legendary',
            price = 3400,
            style = 'solid',
            art = 'wings',
            width = 2,
            color = '#EAF1F8',
            color2 = '#F5C542',
            glow = 22
        },
        {
            id = 'champion',
            name = 'Champion',
            rarity = 'legendary',
            price = 3800,
            style = 'double',
            art = 'laurel',
            width = 2,
            color = '#F5C542',
            color2 = '#FFE9A8',
            glow = 20
        },

        -- ---- الأنصاف الي تطابق إطار بنفس الاسم ----
        {
            id = 'void',
            name = 'Void',
            rarity = 'epic',
            price = 1600,
            style = 'spin',
            width = 3,
            color = '#C158FF',
            color2 = '#3FA9FF',
            speed = 5,
            glow = 18
        },
        {
            id = 'solar',
            name = 'Solar',
            rarity = 'epic',
            price = 1700,
            style = 'halo',
            width = 4,
            color = '#FFD24A',
            color2 = '#FF4757',
            glow = 24
        },
        {
            id = 'briar',
            name = 'Briar',
            rarity = 'legendary',
            price = 3000,
            style = 'solid',
            art = 'vines',
            width = 2,
            color = '#C158FF',
            color2 = '#2FDD9B',
            glow = 18
        },
        {
            id = 'forge',
            name = 'Forge',
            rarity = 'legendary',
            price = 3200,
            style = 'solid',
            art = 'flames',
            width = 3,
            color = '#FF7A3C',
            color2 = '#FFD24A',
            glow = 22
        }
    }

}

Config.Rewards          = {
    enabled = true, -- تشغيل الجوائز

    -- تنعطى بنهاية كل قيم مصنّفة
    perMatch = {
        winMoney      = 2500, -- فلوس الفوز
        lossMoney     = 800, -- فلوس الخسارة
        mvpMoney      = 1500, -- فلوس أفضل لاعب
        xpWin         = 120, -- خبرة الفوز
        xpLoss        = 45, -- خبرة الخسارة
        xpPerKill     = 6, -- خبرة كل قتلة
        xpPerHeadshot = 4, -- خبرة كل هيدشوت
        xpMVP         = 60 -- خبرة أفضل لاعب
    },

    -- جوائز نهاية الموسم حسب أعلى درجة وصلها اللاعب
    season = {
        IRON      = { { type = 'money', value = 25000 }, { type = 'title', value = 'Iron Contender' } },
        BRONZE    = { { type = 'money', value = 50000 }, { type = 'title', value = 'Bronze Contender' } },
        SILVER    = { { type = 'money', value = 100000 }, { type = 'title', value = 'Silver Contender' } },
        GOLD      = { { type = 'money', value = 200000 }, { type = 'title', value = 'Gold Elite' }, { type = 'badge', value = 'gold_season' } },
        PLATINUM  = { { type = 'money', value = 350000 }, { type = 'title', value = 'Platinum Elite' }, { type = 'badge', value = 'plat_season' } },
        DIAMOND   = { { type = 'money', value = 600000 }, { type = 'title', value = 'Diamond Elite' }, { type = 'frame', value = 'diamond' } },
        ASCENDANT = { { type = 'money', value = 900000 }, { type = 'title', value = 'Ascendant' }, { type = 'frame', value = 'ascendant' } },
        IMMORTAL  = { { type = 'money', value = 1500000 }, { type = 'title', value = 'Immortal' }, { type = 'effect', value = 'immortal_aura' } },
        RADIANT   = { { type = 'money', value = 2500000 }, { type = 'title', value = 'Radiant' }, { type = 'effect', value = 'radiant_aura' }, { type = 'vehicle', value = 'zentorno' } }
    },

    -- المستويات
    levels = {
        enabled      = true, -- تشغيل نظام المستويات
        baseXP       = 1000, -- خبرة أول مستوى
        growth       = 1.12, -- الخبرة المطلوبة = baseXP × growth^(المستوى-1)
        maxLevel     = 100, -- أعلى مستوى
        levelRewards = {    -- جوائز عند مستويات محددة
            [10]  = { { type = 'title', value = 'Rookie' } },
            [25]  = { { type = 'money', value = 100000 } },
            [50]  = { { type = 'badge', value = 'veteran' }, { type = 'money', value = 250000 } },
            [75]  = { { type = 'frame', value = 'veteran' } },
            [100] = { { type = 'title', value = 'Legend' }, { type = 'money', value = 1000000 } }
        }
    },

    -- منع التكرار: الجائزة الوحدة ما تنعطى إلا مرة بالموسم
    uniquePerSeason = true
}

-- ============================================================================
-- ٢٤. المهام والإنجازات
-- ============================================================================

Config.Missions         = {
    enabled = true,    -- تشغيل المهام

    daily = {          -- المهام اليومية
        count = 3,     -- كم مهمة تنعطى باليوم
        resetHour = 0, -- ساعة التصفير بتوقيت UTC
        pool = {       -- بركة المهام الي ينختار منها
            { key = 'daily_kills',   label = 'Get 25 kills',         target = 25,   stat = 'kills',     xp = 150, money = 25000 },
            { key = 'daily_hs',      label = 'Get 10 headshots',     target = 10,   stat = 'headshots', xp = 180, money = 30000 },
            { key = 'daily_wins',    label = 'Win 2 ranked matches', target = 2,    stat = 'wins',      xp = 200, money = 40000 },
            { key = 'daily_damage',  label = 'Deal 5000 damage',     target = 5000, stat = 'damage',    xp = 150, money = 25000 },
            { key = 'daily_matches', label = 'Play 3 matches',       target = 3,    stat = 'matches',   xp = 120, money = 20000 },
            { key = 'daily_mvp',     label = 'Earn 1 MVP',           target = 1,    stat = 'mvp',       xp = 250, money = 50000 }
        }
    },

    weekly = {        -- المهام الأسبوعية
        count = 3,    -- كم مهمة بالأسبوع
        resetDay = 1, -- يوم التصفير (١ = الاثنين)
        pool = {      -- بركة المهام الأسبوعية
            { key = 'weekly_kills',   label = 'Get 150 kills',         target = 150, stat = 'kills',     xp = 800,  money = 150000 },
            { key = 'weekly_wins',    label = 'Win 10 ranked matches', target = 10,  stat = 'wins',      xp = 1200, money = 250000 },
            { key = 'weekly_hs',      label = 'Get 60 headshots',      target = 60,  stat = 'headshots', xp = 1000, money = 200000 },
            { key = 'weekly_mvp',     label = 'Earn 5 MVPs',           target = 5,   stat = 'mvp',       xp = 1500, money = 300000 },
            { key = 'weekly_matches', label = 'Play 20 matches',       target = 20,  stat = 'matches',   xp = 700,  money = 120000 }
        }
    }
}

-- الإنجازات: المفتاح، والاسم، والوصف، والإحصائية المتابعة، والهدف، والخبرة
Config.Achievements     = {
    { key = 'first_blood_10', label = 'Opening Act',   desc = 'Get 10 first bloods',      stat = 'first_bloods',    target = 10,   xp = 300 },
    { key = 'ace_1',          label = 'Ace',           desc = 'Win a round alone vs all', stat = 'aces',            target = 1,    xp = 500 },
    { key = 'ace_10',         label = 'Ace Machine',   desc = 'Get 10 aces',              stat = 'aces',            target = 10,   xp = 1500 },
    { key = 'clutch_25',      label = 'Clutch King',   desc = 'Win 25 clutches',          stat = 'clutches',        target = 25,   xp = 1200 },
    { key = 'kills_1000',     label = 'Executioner',   desc = 'Get 1000 kills',           stat = 'kills',           target = 1000, xp = 2000 },
    { key = 'hs_500',         label = 'Headhunter',    desc = 'Get 500 headshots',        stat = 'headshots',       target = 500,  xp = 2000 },
    { key = 'wins_100',       label = 'Centurion',     desc = 'Win 100 matches',          stat = 'wins',            target = 100,  xp = 2500 },
    { key = 'mvp_50',         label = 'Most Valuable', desc = 'Earn 50 MVPs',             stat = 'mvp',             target = 50,   xp = 2500 },
    { key = 'streak_10',      label = 'Unstoppable',   desc = 'Win 10 matches in a row',  stat = 'best_win_streak', target = 10,   xp = 3000 }
}

-- ============================================================================
-- ٢٥. القروب
-- ============================================================================

Config.Party            = {
    enabled              = true, -- تشغيل نظام القروب
    maxSize              = 5, -- أكثر عدد أعضاء
    inviteTimeout        = 30, -- ثواني قبل ما تنتهي الدعوة
    requireReady         = true, -- الكل لازم يضغط جاهز
    -- يفكك القروب لما يطلع القائد بدل ما ينقل القيادة لواحد ثاني
    disbandOnLeaderLeave = false,
    -- أعضاء القروب لازم يكونون داخل هذا الفرق برقم الرانك
    rankGap              = 5,
    rankGapEnabled       = true, -- تشغيل القيد
    -- مسافة الدعوة المطلوبة (0 = من أي مكان بالسيرفر)
    inviteDistance       = 0.0
}

-- ============================================================================
-- ٢٦. الغرف الخاصة
-- ============================================================================

Config.CustomGames      = {
    enabled           = true, -- تشغيل الغرف الخاصة
    maxRooms          = 25,   -- أكثر عدد غرف بنفس الوقت
    maxPlayersPerRoom = 20,   -- أكثر عدد لاعبين بالغرفة
    requirePermission = false, -- إذا true تنفحص صلاحية Config.Permissions.createCustom
    roomNameMaxLength = 28,   -- أطول اسم غرفة
    passwordMaxLength = 20,   -- أطول كلمة سر
    idleTimeout       = 900,  -- ثواني قبل ما تنحذف الغرفة الفاضية

    -- الغرف الخاصة ما تأثر على الرانك إلا إذا شغّلها الطاقم
    rankedAllowed     = false,
    rankedPermission  = 'pvp.admin', -- الصلاحية المطلوبة لتشغيلها مصنّفة

    -- إعدادات الغرفة الافتراضية (المضيف يقدر يغيّر كل وحدة منها)
    -- كود قصير وسهل للانضمام، يستخدمه زر JOIN CODE بالواجهة
    roomCode          = {
        length   = 4,                                 -- طول الكود
        alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' -- بدون I و O و 0 و 1
    },

    -- أنواع القيم المعروضة بواجهة الغرف الخاصة
    matchTypes        = {
        { id = 'normal',  label = 'Normal',   description = 'Everyone spawns with the selected weapons.' },
        { id = 'random',  label = 'Random',   description = 'A random weapon from the selection each round.' },
        { id = 'gungame', label = 'Gun Game', description = 'Every kill advances you to the next weapon.' }
    },

    defaults          = {
        mode            = '5v5',          -- الطور
        map             = 'harbor',       -- الماب
        matchType       = 'normal',       -- نوع القيم
        weapons         = { 'pistol_mk2' }, -- الأسلحة المختارة
        armorEnabled    = false,          -- الدرع
        headshotOnly    = false,          -- الرأس فقط
        rounds          = 13,             -- عدد الراوندات
        roundTime       = 120,            -- وقت الراوند بالثواني
        matchTime       = 3600,           -- وقت القيم بالثواني
        killLimit       = 0,              -- حد القتلات
        friendlyFire    = false,          -- ضرر الزملاء
        headshotOneShot = true,           -- الهيدشوت يقتل بطلقة
        health          = 100,            -- الدم
        armor           = 0,              -- الدرع
        movement        = 1.0,            -- سرعة الحركة
        jump            = true,           -- القفز
        respawn         = false,          -- الرسبن
        respawnTime     = 4,              -- ثواني الرسبن
        lives           = 1,              -- عدد الأرواح
        spectators      = true,           -- السماح بالمشاهدين
        teamBalance     = true,           -- موازنة الفرق
        autoStart       = true,           -- بداية تلقائية
        autoStartAt     = 1.0,            -- نسبة امتلاء الأماكن الي تبدأ عندها
        minimap         = false,          -- الخريطة الصغيرة
        vehicles        = false,          -- السيارات
        killcam         = false,          -- كام القتل
        overtime        = true,           -- الوقت الإضافي
        suddenDeath     = true,           -- الراوند الحاسم
        loadout         = 'standard',     -- السلاح الافتراضي
        locked          = false           -- الغرفة مقفولة بكلمة سر
    },

    -- حدود ما يقدر المضيف يتعداها
    limits            = {
        rounds      = { min = 1, max = 31 },
        roundTime   = { min = 30, max = 600 },
        matchTime   = { min = 60, max = 5400 },
        killLimit   = { min = 0, max = 300 },
        health      = { min = 50, max = 200 },
        armor       = { min = 0, max = 100 },
        movement    = { min = 0.8, max = 1.6 },
        lives       = { min = 1, max = 10 },
        respawnTime = { min = 1, max = 30 }
    }
}

-- ============================================================================
-- ٢٧. المشاهدة
-- ============================================================================

Config.SpectatorRules   = {
    enabled           = true,
    -- اللاعب الميت ما يشاهد إلا فريقه
    teamOnly          = true,
    -- الطاقم الي عنده صلاحية المشاهدة يشوف الكل
    staffFreeSpectate = true,
    -- تأخير قبل ما يدخل الميت وضع المشاهدة (نافذة كام القتل)
    deathDelay        = 1,
    -- السماح بالكاميرا الحرة للطاقم
    staffFreecam      = true
}

-- ============================================================================
-- ٢٨. الكيل فيد والأحداث الإضافية
-- ============================================================================

Config.CombatEvents     = {
    firstBlood   = { enabled = true, xp = 15 },                     -- أول دم بالراوند
    doubleKill   = { enabled = true, window = 5000, xp = 20 },      -- قتلتين متتاليتين
    tripleKill   = { enabled = true, window = 5000, xp = 35 },      -- ثلاث قتلات
    quadraKill   = { enabled = true, window = 5000, xp = 55 },      -- أربع قتلات
    ace          = { enabled = true, xp = 100 },                    -- قتل الفريق كله لحاله
    clutch       = { enabled = true, xp = 60 },                     -- حسم الراوند وهو آخر واحد
    revenge      = { enabled = true, xp = 10 },                     -- ثأر من الي قتله
    nemesis      = { enabled = true, threshold = 3 },               -- خصم يقتله متكرر
    killStreak   = { enabled = true, steps = { 3, 5, 7, 10, 15 } }, -- سلاسل القتل
    commendation = { enabled = true, perMatch = 1 }                 -- إشادة بلاعب بكل قيم
}

-- ============================================================================
-- ٢٩. أفضل لاعب (MVP)
-- ============================================================================

Config.MVP              = {
    enabled = true, -- تشغيل اختيار أفضل لاعب
    weights = {     -- وزن كل إحصائية بحساب النقاط
        kills       = 3.0,
        deaths      = -1.5,
        damage      = 0.012,
        headshots   = 1.5,
        objective   = 2.5,
        roundsWon   = 1.0,
        clutches    = 4.0,
        assists     = 0.8,
        firstBloods = 1.2
    },
    -- إذا true ما ياخذ أفضل لاعب إلا من الفريق الفايز
    winnerOnly = false
}

-- ============================================================================
-- ٣٠. الأمان وحدود الطلبات
-- ============================================================================

Config.Security         = {
    -- لكل لاعب ولكل حدث: كم طلب مسموح داخل المدة (max عدد، window ملي ثانية)
    rateLimits             = {
        default     = { max = 20, window = 10000 },
        menu        = { max = 10, window = 10000 },
        queue       = { max = 8, window = 10000 },
        party       = { max = 20, window = 10000 },
        custom      = { max = 25, window = 10000 },
        kill        = { max = 40, window = 5000 },
        damage      = { max = 200, window = 5000 },
        headshot    = { max = 30, window = 5000 },
        leaderboard = { max = 12, window = 10000 },
        profile     = { max = 15, window = 10000 },
        admin       = { max = 40, window = 10000 },
        settings    = { max = 6, window = 10000 },
        chat        = { max = 10, window = 10000 }
    },

    -- الإجراء التلقائي لما يغرق اللاعب السيرفر بالأحداث
    floodAction            = 'ignore', -- 'ignore' تجاهل أو 'kick' طرد أو 'flag' بلاغ
    floodKickAfter         = 6, -- كم مخالفة متتالية قبل الإجراء

    -- يرفض بلاغات الضرر الي فوق هذي القيمة (للضربة الوحدة)
    maxSingleDamage        = 400,
    -- يرفض ادعاء القتل إذا الضحية ما انضرب قريب
    killDamageWindow       = 4000,

    -- يتأكد إن السلاح المبلّغ عنه فعلاً بيد المهاجم
    validateEquippedWeapon = true,

    -- يسجّل كل حدث مرفوض
    logRejections          = true
}

-- ============================================================================
-- ٣١. الكوماندات
-- ============================================================================

Config.Commands         = {
    pvp          = { enabled = true, name = 'pvp', permission = nil },
    rank         = { enabled = true, name = 'rank', permission = nil },
    leaderboard  = { enabled = true, name = 'leaderboard', permission = nil },
    customgame   = { enabled = true, name = 'customgame', permission = nil },
    reconnectpvp = { enabled = true, name = 'reconnectpvp', permission = nil },
    -- هذي محكومة بـ Config.AdminActions، مو بحقل permission هنا.
    pvpadmin     = { enabled = true, name = 'pvpadmint', permission = nil },
    rankban      = { enabled = true, name = 'rankban', permission = nil },
    rankunban    = { enabled = true, name = 'rankunban', permission = nil },
    setrank      = { enabled = true, name = 'setrank', permission = nil },
    setrp        = { enabled = true, name = 'setrp', permission = nil },
    givepvprp    = { enabled = true, name = 'givepvprp', permission = nil },
    pvpstatus    = { enabled = true, name = 'pvpstatus', permission = 'pvp.moderator' },
    -- تقرير الأداء: وين راح وقت السيرفر. اكتب /pvpperf يطبع لك التقرير بالشات،
    -- و /pvpperf reset يصفّر العدادات عشان تقيس شي محدد. ونفسه بالكونسول
    -- بالأمر m5perf و m5perf reset.
    pvpperf      = { enabled = true, name = 'pvpperf', permission = 'pvp.moderator' }
}

-- ============================================================================
-- ٣٢. المفاتيح العامة
-- ============================================================================

Config.Global           = {
    -- تجميد البحث بالرانكد (وقت الصيانة)
    rankedFrozen  = false,
    frozenMessage = 'Ranked is temporarily disabled by the administration.',  -- الرسالة الي تطلع

    -- أقل مستوى ووقت لعب قبل ما ينفتح الرانكد
    requirements  = {
        enabled     = false, -- تشغيل الشروط
        minLevel    = 0,     -- أقل مستوى
        minPlaytime = 0      -- أقل وقت لعب بالثواني
    },

    -- إعلان الأحداث الكبيرة بشات السيرفر
    announce      = {
        radiantPromotion = true, -- الوصول لرانك Radiant
        aces             = true, -- قتل الفريق كله لحاله
        winStreaks       = 10    -- سلسلة فوز من هذا الطول فوق
    }
}
