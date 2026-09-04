--[[
    ============================================================================
     M5 Ranked PvP — Locale.lua
    ----------------------------------------------------------------------------
     Every line of text the script shows a player lives here: notifications,
     errors, the whole menu, the match HUD and the scoreboard. Nothing
     user-facing is written anywhere else, so this is the only file to touch to
     change wording or add a language.

     How it works
        The English text IS the key. `Locale.ar['Party is full.']` is the Arabic
        for it. Anything without a translation falls back to the English key
        unchanged, so a missing line is never a blank screen and adding a
        language can be done a few lines at a time.

        %s and %d are filled in by the script. Keep them, and keep them in the
        same order as the English line — Arabic reads right to left but the
        placeholders are still substituted left to right.

     Adding a language
        1. Copy the `ar` block, rename it (e.g. `Locale.fr = { ... }`).
        2. Add its code to Locale.available below.
        3. Set Locale.default, or leave players to pick it in Settings.

     This file is loaded on the client and the server, and the client hands the
     active table to the interface, so one edit reaches all three.
    ============================================================================
]]

Locale = {}

-- Language used before a player chooses one: 'en' or 'ar' (or your own).
Locale.default = 'ar'

-- Fallback for any line the active language is missing. Leave as 'en'.
Locale.fallback = 'en'

-- Offered in Settings > Language. Remove one to hide it.
Locale.available = {
    { id = 'en', label = 'English' },
    { id = 'ar', label = 'العربية' }
}

-- Right to left languages. The interface mirrors itself for these.
Locale.rtl = { ar = true }

-- Language for notifications only (the toasts in the corner), whatever the
-- player has the interface set to. Useful when the server is Arabic speaking
-- but you still want the menu available in English.
--
--   'ar'  every notification is Arabic, always
--   nil   notifications follow the player's chosen language
Locale.notifications = 'ar'

-- ============================================================================
-- ENGLISH — the keys. Change the text here only if you want different English;
-- if you rename a key you must rename it in every other language too.
-- ============================================================================

Locale.en = {}   -- empty on purpose: the key is the English text

-- ============================================================================
-- ARABIC
-- ============================================================================

Locale.ar = {

    -- ---------------------------------------------------------------- queue
    ['SEARCHING']                 = 'جاري البحث',
    ['SEARCHING FOR MATCH']       = 'جاري البحث عن مباراة',
    ['MATCH FOUND']               = 'تم إيجاد مباراة',
    ['QUEUE']                     = 'الطابور',
    ['QUEUE TIMEOUT']             = 'انتهت مهلة البحث',
    ['MATCH CANCELLED']           = 'أُلغيت المباراة',
    ['No match was found. Please try again.'] = 'لم يتم إيجاد مباراة. حاول مرة أخرى.',
    ['A player failed to accept. You were placed back in the queue.'] =
        'أحد اللاعبين لم يقبل. تمت إعادتك إلى الطابور.',
    ['You did not accept the match.'] = 'لم تقبل المباراة.',
    ['The match could not be created. Please queue again.'] =
        'تعذّر إنشاء المباراة. ابحث مرة أخرى.',
    ['Party size changed — the search was cancelled.'] =
        'تغيّر حجم المجموعة — أُلغي البحث.',
    ['Your queue cooldown was cleared.'] = 'تم مسح مهلة انتظار الطابور.',
    ['Only the party leader can start the search.'] = 'قائد المجموعة فقط يبدأ البحث.',
    ['Not available right now.'] = 'غير متاح حاليًا.',

    -- ---------------------------------------------------------------- party
    ['PARTY']                     = 'المجموعة',
    ['PARTY INVITE']              = 'دعوة مجموعة',
    ['Party is full.']            = 'المجموعة ممتلئة.',
    ['Party unavailable.']        = 'المجموعة غير متاحة.',
    ['Party no longer exists.']   = 'لم تعد المجموعة موجودة.',
    ['A party member is not loaded.'] = 'أحد أعضاء المجموعة غير محمّل.',
    ['All party members must be ready.'] = 'يجب أن يكون كل الأعضاء جاهزين.',
    ['Not a party member.']       = 'ليس عضوًا في المجموعة.',
    ['Only the leader can invite.'] = 'القائد فقط يستطيع الدعوة.',
    ['Only the leader can kick.']   = 'القائد فقط يستطيع الطرد.',
    ['Only the leader can transfer.'] = 'القائد فقط يستطيع نقل القيادة.',
    ['You cannot kick yourself.'] = 'لا يمكنك طرد نفسك.',
    ['You are already in a party.'] = 'أنت بالفعل في مجموعة.',
    ['That player is already in a party.'] = 'هذا اللاعب في مجموعة بالفعل.',
    ['That player cannot join parties.'] = 'هذا اللاعب لا يستطيع الانضمام للمجموعات.',
    ['That player is busy.']      = 'هذا اللاعب مشغول.',
    ['You are now the party leader.'] = 'أصبحت قائد المجموعة.',
    ['You were removed from the party.'] = 'تمت إزالتك من المجموعة.',
    ['Your party invitation was declined.'] = 'تم رفض دعوتك.',
    ['Invitation expired.']       = 'انتهت صلاحية الدعوة.',
    ['Rank difference is too large for a party.'] = 'فارق الرتبة كبير جدًا لتكوين مجموعة.',
    ['Party rank difference is too large for ranked.'] =
        'فارق الرتب داخل المجموعة كبير جدًا للمصنّف.',

    -- ---------------------------------------------------------------- match
    ['MATCH']                     = 'المباراة',
    ['M5 RANKED']                 = 'M5 المصنّف',
    ['RANKED']                    = 'مصنّف',
    ['Match not found.']          = 'المباراة غير موجودة.',
    ['No live match.']            = 'لا توجد مباراة جارية.',
    ['That match has already ended.'] = 'انتهت هذه المباراة بالفعل.',
    ['The match is already running.'] = 'المباراة جارية بالفعل.',
    ['That player is not in a match.'] = 'هذا اللاعب ليس في مباراة.',
    ['You are no longer part of that match.'] = 'لم تعد جزءًا من تلك المباراة.',
    ['You were removed from the match for inactivity.'] = 'تمت إزالتك من المباراة بسبب الخمول.',
    ['You were removed from the match: %s'] = 'تمت إزالتك من المباراة: %s',
    ['Leave your current activity first.'] = 'اخرج من نشاطك الحالي أولًا.',
    ['You are already in a match.'] = 'أنت بالفعل داخل مباراة.',
    ['%s disconnected — %ds to reconnect.'] = 'انقطع %s — أمامه %d ثانية للعودة.',
    ['%s reconnected to the match.'] = 'عاد %s إلى المباراة.',
    ['RECONNECT']                 = 'العودة للمباراة',
    ['RECONNECT TO MATCH']        = 'العودة إلى المباراة',
    ['No match to reconnect to.'] = 'لا توجد مباراة للعودة إليها.',
    ['The reconnect window has expired.'] = 'انتهت مهلة العودة.',
    ['SURRENDER']                 = 'استسلام',
    ['Surrender is disabled.']    = 'الاستسلام معطّل.',
    ['HOLD TO SURRENDER']         = 'استمر بالضغط للانسحاب',
    ['At least two players are required.'] = 'مطلوب لاعبان على الأقل.',

    -- ---------------------------------------------------------------- rounds
    ['ROUND']                     = 'الجولة',
    ['ROUND 1']                   = 'الجولة 1',
    ['OVERTIME']                  = 'وقت إضافي',
    ['SUDDEN DEATH']              = 'الموت المفاجئ',
    ['GO']                        = 'ابدأ',
    ['GET READY']                 = 'استعد',
    ['ROUND WON']                 = 'فزت بالجولة',
    ['ROUND LOST']                = 'خسرت الجولة',
    ['MATCH POINT']               = 'نقطة الحسم',
    ['ELIMINATION']               = 'إقصاء',
    ['TIME']                      = 'انتهى الوقت',
    ['VICTORY']                   = 'فوز',
    ['DEFEAT']                    = 'خسارة',
    ['DRAW']                      = 'تعادل',
    ['ELIMINATED']                = 'تم إقصاؤك',
    ['FREE FOR ALL']              = 'الكل ضد الكل',
    ['ALIVE']                     = 'على قيد الحياة',
    ['SPECTATING']                = 'مشاهدة',
    ['WARNING']                   = 'تحذير',
    ['RETURN TO COMBAT ZONE']     = 'عد إلى منطقة القتال',
    ['AFK WARNING — MOVE NOW']    = 'تحذير خمول — تحرك الآن',

    -- ---------------------------------------------------------------- ranks / RP
    ['RP']                        = 'النقاط',
    ['PENALTY']                   = 'عقوبة',
    ['Unranked']                  = 'بدون رتبة',
    ['%s%d RP — %s']              = '%s%d نقطة — %s',
    ['%s%d RP → %d total.']       = '%s%d نقطة ← %d بالمجموع.',
    ['%s — %d RP%s']              = '%s — %d نقطة%s',
    ['%s penalty: -%d RP%s']      = 'عقوبة %s: -%d نقطة%s',
    ['Your rank was set to %s — %s'] = 'تم ضبط رتبتك إلى %s — %s',
    ['Your RP was set to %d — %s']   = 'تم ضبط نقاطك إلى %d — %s',
    ['Your season stats were reset — %s'] = 'تمت إعادة تعيين إحصائيات موسمك — %s',
    ['Your ranked ban has been removed.'] = 'تم رفع حظرك من المصنّف.',
    ['UNBANNED']                  = 'رُفع الحظر',

    -- ---------------------------------------------------------------- progression
    ['PROGRESSION']               = 'التقدّم',
    ['LEVEL UP']                  = 'ترقية مستوى',
    ['ACHIEVEMENT']               = 'إنجاز',
    ['REWARDS']                   = 'المكافآت',
    ['You reached level %d']      = 'وصلت إلى المستوى %d',
    ['+%d XP — %s']               = '+%d خبرة — %s',
    ['Achievement unlocked: %s']  = 'إنجاز مفتوح: %s',
    ['Mission complete: %s']      = 'مهمة مكتملة: %s',
    ['Reward claimed.']           = 'تم استلام المكافأة.',
    ['Nothing to claim.']         = 'لا يوجد ما تستلمه.',
    ['Available from round %d.']  = 'متاح من الجولة %d.',

    -- ---------------------------------------------------------------- custom games
    ['CUSTOM GAME']               = 'مباراة مخصصة',
    ['Custom games are disabled.'] = 'المباريات المخصصة معطّلة.',
    ['You do not have permission to create custom games.'] =
        'ليس لديك صلاحية إنشاء مباريات مخصصة.',
    ['You are banned from custom games.'] = 'أنت محظور من المباريات المخصصة.',
    ['You are banned from this room.'] = 'أنت محظور من هذه الغرفة.',
    ['You are already in a room.'] = 'أنت بالفعل في غرفة.',
    ['You are not in a room.']    = 'أنت لست في غرفة.',
    ['Room not found.']           = 'الغرفة غير موجودة.',
    ['No room with that code.']   = 'لا توجد غرفة بهذا الكود.',
    ['The room is full.']         = 'الغرفة ممتلئة.',
    ['The room is locked.']       = 'الغرفة مقفلة.',
    ['Wrong password.']           = 'كلمة المرور خاطئة.',
    ['The custom game server is full.'] = 'خوادم المباريات المخصصة ممتلئة.',
    ['Only the host can do that.'] = 'المضيف فقط يستطيع ذلك.',
    ['You are now the room host.'] = 'أصبحت مضيف الغرفة.',
    ['Player not in the room.']   = 'اللاعب ليس في الغرفة.',
    ['You were kicked from the room.'] = 'تم طردك من الغرفة.',
    ['You were banned from the room.'] = 'تم حظرك من الغرفة.',
    ['The custom room was closed.'] = 'تم إغلاق الغرفة المخصصة.',

    -- ---------------------------------------------------------------- maps / votes
    ['MAP VOTE']                  = 'تصويت الخريطة',
    ['SELECT A MAP']              = 'اختر خريطة',
    ['Unknown map.']              = 'خريطة غير معروفة.',
    ['No map is available.']      = 'لا توجد خريطة متاحة.',
    ['That map does not support this mode.'] = 'هذه الخريطة لا تدعم هذا النمط.',
    ['A vote is already running.'] = 'يوجد تصويت جارٍ بالفعل.',
    ['Please wait before voting again.'] = 'انتظر قليلًا قبل التصويت مجددًا.',
    ['Unknown mode.']             = 'نمط غير معروف.',
    ['Invalid team.']             = 'فريق غير صالح.',

    -- ---------------------------------------------------------------- training / bots
    ['TRAINING']                  = 'التدريب',
    ['Training is disabled.']     = 'التدريب معطّل.',
    ['EXIT TRAINING']             = 'الخروج من التدريب',
    ['You are not in the training range.'] = 'أنت لست في ميدان التدريب.',
    ['Bot matches are disabled.'] = 'مباريات البوت معطّلة.',
    ['You are already in a bot match.'] = 'أنت بالفعل في مباراة بوت.',
    ['No bot match is running.']  = 'لا توجد مباراة بوت جارية.',
    ['You must be in game to start one.'] = 'يجب أن تكون داخل اللعبة لبدئها.',
    ['No free routing bucket for a bot match.'] = 'لا يوجد عالم شاغر لمباراة بوت.',
    ['Could not load the bot model.'] = 'تعذّر تحميل نموذج البوت.',
    ['BOT MATCH']                 = 'مباراة بوت',

    -- ---------------------------------------------------------------- social
    ['REPORT']                    = 'بلاغ',
    ['COMMEND']                   = 'إشادة',
    ['AVOID']                     = 'تجنّب',
    ['Your report has been submitted.'] = 'تم إرسال بلاغك.',
    ['Commendation sent.']        = 'تم إرسال الإشادة.',
    ['Player added to your avoid list.'] = 'تمت إضافة اللاعب لقائمة التجنّب.',
    ['Your avoid list is full.']  = 'قائمة التجنّب ممتلئة.',
    ['No data for that player.']  = 'لا توجد بيانات لهذا اللاعب.',
    ['Player not found.']         = 'اللاعب غير موجود.',
    ['Player not loaded.']        = 'اللاعب غير محمّل.',
    ['Player data unavailable.']  = 'بيانات اللاعب غير متاحة.',
    ['SPECTATE']                  = 'مشاهدة',

    -- ---------------------------------------------------------------- admin
    ['ADMIN']                     = 'الإدارة',
    ['You do not have access to the admin panel.'] = 'ليس لديك صلاحية دخول قائمة الإدارة.',
    ['You do not have permission to use this command.'] = 'ليس لديك صلاحية استخدام هذا الأمر.',
    ['No permission (%s).']       = 'لا توجد صلاحية (%s).',
    ['Unknown admin action.']     = 'إجراء إداري غير معروف.',
    ['Unknown action.']           = 'إجراء غير معروف.',
    ['Action failed.']            = 'فشل الإجراء.',
    ['Action applied.']           = 'تم تنفيذ الإجراء.',
    ['Invalid target.']           = 'هدف غير صالح.',
    ['Invalid target or rank.']   = 'الهدف أو الرتبة غير صالح.',
    ['Invalid target or value.']  = 'الهدف أو القيمة غير صالح.',
    ['No player with that ID.']   = 'لا يوجد لاعب بهذا الرقم.',
    ['Enter an amount.']          = 'أدخل قيمة.',
    ['Maximum is %d RP per action.'] = 'الحد الأقصى %d نقطة لكل إجراء.',
    ['Maximum is %d XP per action.'] = 'الحد الأقصى %d خبرة لكل إجراء.',
    ['A reason is required for this action.'] = 'هذا الإجراء يتطلب سببًا.',
    ['Enter a player ID first.']  = 'أدخل رقم اللاعب أولًا.',
    ['TARGET PLAYER']             = 'اللاعب المستهدف',
    ['PLAYER ID']                 = 'رقم اللاعب',
    ['REASON']                    = 'السبب',
    ['STATUS']                    = 'الحالة',
    ['LOAD']                      = 'تحميل',
    ['no player loaded']          = 'لم يُحمَّل لاعب',
    ['APPLY']                     = 'تنفيذ',
    ['REFRESH']                   = 'تحديث',
    ['MONITOR']                   = 'المراقبة',
    ['MATCHES']                   = 'المباريات',
    ['POINTS']                    = 'النقاط',
    ['PUNISH']                    = 'العقوبات',
    ['SYSTEM']                    = 'النظام',
    ['Start Bot Match']           = 'بدء مباراة ضد بوت',
    ['Stop Bot Match']            = 'إيقاف مباراة البوت',
    ['Ends your practice session and returns you to the world.'] =
        'ينهي جلسة التدريب ويعيدك إلى العالم.',
    ['Practice duel against AI on your own screen. Always unranked — no RP, MMR or stats.'] =
        'مبارزة تدريبية ضد الذكاء الاصطناعي على شاشتك. غير مصنّفة دائمًا — بلا نقاط أو MMR أو إحصائيات.',
    ['PVP STATUS']                = 'حالة النظام',
    ['Matches: %d • Searching: %d • Rooms: %d • Online profiles: %d • Season: %s'] =
        'المباريات: %d • يبحثون: %d • الغرف: %d • الملفات المتصلة: %d • الموسم: %s',

    -- ---------------------------------------------------------------- interface
    ['MATCHMAKING']               = 'المطابقة',
    ['LEADERBOARD']               = 'لوحة الصدارة',
    ['CUSTOM MATCH']              = 'مباراة مخصصة',
    ['PROFILE']                   = 'الملف الشخصي',
    ['HISTORY']                   = 'السجل',
    ['SETTINGS']                  = 'الإعدادات',
    ['START']                     = 'ابدأ',
    ['CANCEL']                    = 'إلغاء',
    ['Cancel']                    = 'إلغاء',
    ['Confirm']                   = 'تأكيد',
    ['ACCEPT']                    = 'قبول',
    ['DECLINE']                   = 'رفض',
    ['READY']                     = 'جاهز',
    ['NOT READY']                 = 'غير جاهز',
    ['WAITING FOR OTHER PLAYERS…'] = 'بانتظار بقية اللاعبين…',
    ['INVITE PLAYER']             = 'دعوة لاعب',
    ['CLICK TO INVITE']           = 'اضغط للدعوة',
    ['OPEN SLOT']                 = 'مقعد شاغر',
    ['SLOT LOCKED']               = 'مقعد مقفل',
    ['LEADER ONLY']               = 'القائد فقط',
    ['INVITE IN ORDER']           = 'املأ المقعد السابق أولًا',
    ['SEND INVITE']               = 'إرسال الدعوة',
    ['Enter the server ID of the player you want in your party.'] =
        'أدخل رقم اللاعب في السيرفر لإضافته إلى مجموعتك.',
    ['NO PLAYERS']                = 'لا يوجد لاعبون',
    ['PLAYER']                    = 'اللاعب',
    ['TEAM A']                    = 'الفريق أ',
    ['TEAM B']                    = 'الفريق ب',
    ['K']                         = 'قتل',
    ['D']                         = 'موت',
    ['A']                         = 'مساعدة',
    ['HS']                        = 'هيد',
    ['DMG']                       = 'ضرر',
    ['PING']                      = 'البنق',
    ['HOLD']                      = 'استمر بالضغط على',
    ['MATCH SETTINGS']            = 'إعدادات المباراة',
    ['GAME MODE']                 = 'نمط اللعب',
    ['ROUNDS']                    = 'الجولات',
    ['MATCH TYPE']                = 'نوع المباراة',
    ['WEAPONS']                   = 'الأسلحة',
    ['ARMOR']                     = 'الدرع',
    ['HEADSHOT ONLY']             = 'هيدشوت فقط',
    ['SELECT MAP']                = 'اختر الخريطة',
    ['ACHIEVEMENTS']              = 'الإنجازات',
    ['UNLOCKED']                  = 'مفتوح',
    ['LOCKED']                    = 'مقفل',
    ['BOT']                       = 'بوت',
    ['BOTS']                      = 'بوتات',
    ['RANDOM MAP']                = 'خريطة عشوائية',
    ['STOP']                      = 'إيقاف',
    ['[E] Open M5 Ranked PvP']    = '[E] فتح M5 Ranked PvP',
    ['You do not have access to this feature.'] = 'ليس لديك صلاحية.',
    ['Screen effects cleared.']   = 'تم مسح تأثيرات الشاشة.',
    -- ---------------------------------------------------------------- settings
    ['LANGUAGE']                  = 'اللغة',
    ['UI VOLUME']                 = 'صوت الواجهة',
    ['MUSIC VOLUME']              = 'صوت الموسيقى',
    ['KILL SOUNDS']               = 'أصوات القتل',
    ['HUD SIZE']                  = 'حجم الهود',
    ['KILL FEED SIDE']            = 'جهة سجل القتل',
    ['SHOW PING']                 = 'إظهار البنق',
    ['MINIMAP IN MATCH']          = 'الخريطة داخل المباراة',
    ['AUTO SPECTATE']             = 'المشاهدة التلقائية',
    ['TEAM A COLOUR']             = 'لون الفريق أ',
    ['TEAM B COLOUR']             = 'لون الفريق ب',
    ['VISUAL EFFECTS']            = 'المؤثرات البصرية',
    ['LOW SPEC MODE']             = 'وضع الأجهزة الضعيفة',

    -- ---------------------------------------------------------------- pages
    ['Ranked']                    = 'المصنّف',
    ['Leaderboard']               = 'لوحة الصدارة',
    ['Custom Match']              = 'مباراة مخصصة',
    ['Profile']                   = 'الملف الشخصي',
    ['History']                   = 'السجل',
    ['Rewards']                   = 'المكافآت',
    ['Training']                  = 'التدريب',
    ['Admin']                     = 'الإدارة',
    ['ADMIN CONTROL']             = 'لوحة الإدارة',
    ['MATCH HISTORY']             = 'سجل المباريات',
    ['YOUR STATISTICS']           = 'إحصائياتك',
    ['PAGE']                      = 'صفحة',

    -- ---------------------------------------------------------------- rooms
    ['CREATE ROOM']               = 'إنشاء غرفة',
    ['LEAVE ROOM']                = 'مغادرة الغرفة',
    ['JOIN CODE']                 = 'دخول بكود',
    ['ROOM CODE']                 = 'كود الغرفة',
    ['Room Code']                 = 'كود الغرفة',
    ['Enter the room code']       = 'أدخل كود الغرفة',
    ['Share the room code with your friends.'] = 'شارك كود الغرفة مع أصدقائك.',

    -- ---------------------------------------------------------------- training modes
    ['AIM TRAINING']              = 'تدريب التصويب',
    ['HEADSHOT TRAINING']         = 'تدريب الهيدشوت',
    ['FREE RANGE']                = 'ميدان حر',

    [' • %d RP to %s']            = ' • %d نقطة حتى %s',
    ['%s: %s']                    = '%s: %s',
    ['YOUR RANK']                 = 'رتبتك',
    ['Usage: /givepvprp <userId> <amount> <reason>'] =
        'الاستخدام: /givepvprp <رقم اللاعب> <القيمة> <السبب>',
    ['English']                   = 'English',
    ['Usage: /%s <userId> <minutes> <reason>'] = 'الاستخدام: /%s <رقم اللاعب> <الدقائق> <السبب>',
    ['Usage: /%s <userId>']       = 'الاستخدام: /%s <رقم اللاعب>',
    ['Usage: /%s <userId> <rankId 0-23> <reason>'] = 'الاستخدام: /%s <رقم اللاعب> <رقم الرتبة 0-23> <السبب>',
    ['Usage: /%s <userId> <rp> <reason>'] = 'الاستخدام: /%s <رقم اللاعب> <النقاط> <السبب>',
    ['NOT SAVED — %s. Check the server console.'] = 'لم يُحفظ — %s. راجع كونسول السيرفر.',
    ['RANK BAN']                  = 'حظر المصنّف',
    ['RANK UNBAN']                = 'رفع حظر المصنّف',
    ['SET RANK']                  = 'ضبط الرتبة',
    ['SET RP']                    = 'ضبط النقاط',
    ['KILLS'] = 'قتل', ['DEATHS'] = 'موت', ['ASSISTS'] = 'مساعدات',
    ['HEADSHOTS'] = 'هيدشوت', ['DAMAGE'] = 'الضرر',

    -- ---------------------------------------------------------------- store
    ['STORE'] = 'المتجر', ['Store'] = 'المتجر',
    ['Cards'] = 'البطاقات', ['Titles'] = 'الألقاب',
    ['BUY'] = 'شراء', ['EQUIP'] = 'تجهيز', ['EQUIPPED'] = 'مُجهّز',
    ['COINS'] = 'العملات',
    ['NOTHING IN THE STORE'] = 'لا توجد عناصر في المتجر',
    ['Spend coins on cards (lobby banner) and titles (shown by your name).'] =
        'اشترِ بالعملات بطاقات (خلفية اللوبي) وألقابًا (تظهر بجانب اسمك).',
    ['Purchase complete.'] = 'تم الشراء.',
    ['Not enough coins.'] = 'العملات غير كافية.',
    ['You already own that.'] = 'تملك هذا العنصر بالفعل.',
    ['You do not own that.'] = 'أنت لا تملك هذا العنصر.',
    ['Unknown item.'] = 'عنصر غير معروف.',
    ['The store is closed.'] = 'المتجر مغلق.',
    ['%s%d coins — %s'] = '%s%d عملة — %s',
    ['Maximum is %d coins per action.'] = 'الحد الأقصى %d عملة لكل إجراء.',
    ['Give Coins'] = 'منح عملات', ['Take Coins'] = 'سحب عملات',
    ['Coins are spent in the Store on cards and titles.'] =
        'العملات تُصرف في المتجر على البطاقات والألقاب.',
    ['FIND MATCH'] = 'ابحث عن مباراة',
    ['Lobby'] = 'اللوبي', ['Career'] = 'المسيرة', ['Custom'] = 'مخصصة',
    ['Aim Train'] = 'تدريب التصويب'
}
