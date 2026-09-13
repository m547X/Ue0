--                                                                                                                                                 --
--                                            M5_iCreator | إعدادات السيرفر فقط - Server Side Only                                             --
--                                                              Made By M547                                                                       --
--                                                         https://discord.gg/MUS                                                                  --

-- ⚠️ هذا الملف يعمل في السيرفر فقط ولا يُرسل للاعبين.
--    ضع فيه كل شيء حساس: التوكنات، روابط الـ API، وروابط الويب هوك، ومسار ملف الجراج.
--
--    مهم: هو مضاف أصلاً داخل server_scripts في fxmanifest.lua قبل Server.lua:
--
--        server_scripts {
--            'Config.lua',
--            'ServerConfig.lua',
--            'Files/Server.lua',
--        }
--
--    ولا تضعه أبداً داخل client_scripts أو shared_scripts وإلا سيتسرب التوكن للاعبين.

ServerConfig = {}

-- ─── Storage ─────────────────────────────────────────────────
-- طريقة حفظ الصور المصغرة:
-- json: يحفظ داخل Files/Data/thumbnails.json.
-- kvp : يحفظ داخل KVP الخاص بالريسرس.
-- api : يرسل البيانات إلى API خارجي (ServerConfig.SaveAPI).
ServerConfig.save = 'json'              -- 'json' | 'kvp' | 'api'

-- ─── Save API ────────────────────────────────────────────────
-- إعدادات الـ API الخارجي المستخدم عند ServerConfig.save = 'api'.
-- saveUrl      : الرابط الذي تُرسل إليه بيانات الصور.
-- loadUrl      : رابط اختياري لجلب الصور المحفوظة عند تشغيل السكربت (GET).
-- method       : نوع الطلب المستخدم عند الحفظ.
-- headers      : هيدرات إضافية مثل التوكن.
-- perVehicle   : true = يرسل كل سيارة بمفردها لحظة تصويرها.
--                false = يرسل جدول الصور كاملاً في كل مرة.
-- mirrorToFile : يحفظ نسخة احتياطية في thumbnails.json بجانب الـ API.
ServerConfig.SaveAPI = {
    saveUrl      = '',
    loadUrl      = '',
    method       = 'POST',
    headers      = {
        ['Authorization'] = '',
    },
    perVehicle   = true,
    mirrorToFile = true,
}

-- ─── GitHub API ──────────────────────────────────────────────
-- يُستخدم عندما تكون Config.ImageHost = 'github'.
-- الصورة تُلتقط عند اللاعب ثم تُرسل للسيرفر، والسيرفر هو من يرفعها
-- إلى المستودع عبر GitHub Contents API، وبذلك يبقى التوكن هنا فقط.
--
-- token         : توكن GitHub (Fine-grained token بصلاحية Contents: Read and write).
--                 الأفضل تركه فارغاً هنا ووضعه في server.cfg:
--                     set m5_github_token "github_pat_xxxxxxxx"
--                 السكربت يقرأ الكونفار m5_github_token تلقائياً إذا كان token فارغاً.
-- owner         : اسم صاحب المستودع أو المنظمة.
-- repo          : اسم المستودع (يجب أن يكون Public حتى تظهر الصور في اللعبة).
-- branch        : اسم البرانش الذي تُرفع إليه الصور.
-- path          : المجلد داخل المستودع (اتركه فارغاً للرفع في الجذر).
-- urlMode       : شكل الرابط الناتج.
--                 raw      = https://raw.githubusercontent.com/owner/repo/branch/path
--                 cdn      = https://cdn.jsdelivr.net/gh/owner/repo@branch/path
--                 download = الرابط الذي يرجعه GitHub نفسه.
-- overwrite     : true = يستبدل الصورة القديمة لنفس السيارة.
-- maxBytes      : أقصى حجم مسموح لصورة واحدة قبل رفضها.
-- commitMessage : رسالة الكومت، %MODEL% تتحول لاسم السيارة.
ServerConfig.GitHub = {
    token         = '',
    owner         = '',
    repo          = '',
    branch        = 'main',
    path          = 'vehicles',
    urlMode       = 'raw',              -- 'raw' | 'cdn' | 'download'
    overwrite     = true,
    maxBytes      = 12000000,
    commitMessage = 'M5_iCreator: %MODEL% thumbnail',
}

-- ─── Vehicle Source ──────────────────────────────────────────
-- من أين يجلب السكربت قائمة السيارات المطلوب تصويرها:
-- config : جدول Config.SqlVehicleTable.
-- sql    : قاعدة البيانات (Config.useSQLvehicle / Config.vehicle_table).
-- garage : من ملف الجراج نفسه (ServerConfig.GarageFile) - وهو الخيار
--          الذي يسحب السيارات التي بدون صورة فقط.
ServerConfig.VehicleSource = 'config'   -- 'config' | 'sql' | 'garage'

-- ─── Garage File ─────────────────────────────────────────────
-- سحب السيارات مباشرة من ملف الجراج.
-- resource : اسم الريسورس الذي يحتوي الملف، مثل vrp أو vrp_garages.
-- path     : مسار الملف داخل ذلك الريسورس، مثل cfg/garages.lua.
--            مثال كامل: resource = 'vrp' و path = 'cfg/garages.lua'
--            سيقرأ: resources/[vrp]/vrp/cfg/garages.lua
--
-- garages           : أسماء جراجات محددة فقط، اتركها {} لقراءة كل الجراجات.
--                     مثال: { "Sonic-garage", "cut-OFF", "كراج الضرب" }
-- skipGarages       : أسماء جراجات تُستثنى دائماً.
-- onlyMissingImages : true = يسحب فقط السيارات التي وسم img فيها فارغ
--                     (<img src='' ... />) ويتجاهل التي لها صورة.
-- skipSaved         : true = يتجاهل أيضاً السيارات التي سبق تصويرها وحُفظت
--                     في thumbnails حتى لو كانت فارغة في الملف.
-- overwriteExisting : عند تصدير الملف المحدّث، هل نستبدل حتى الروابط
--                     الموجودة مسبقاً؟ اتركها false لتعبئة الفاضي فقط.
ServerConfig.GarageFile = {
    resource          = 'vrp',
    path              = 'cfg/garages.lua',
    garages           = {},
    skipGarages       = {},
    onlyMissingImages = true,
    skipSaved         = true,
    overwriteExisting = false,
}

-- ─── Discord Webhook ─────────────────────────────────────────
-- رابط ويب هوك ديسكورد لإرسال إشعار عند حفظ صورة سيارة جديدة.
-- اتركه فارغاً لتعطيل الإشعارات.
ServerConfig.DiscordWebHook = ""

-- ─── Garage Export ───────────────────────────────────────────
-- ويب هوك يرسل سطر الجراج الجاهز للنسخ بعد تصوير كل سيارة،
-- ويرسل الأسطر المحدّثة كاملة بعد انتهاء جلسة التصوير.
-- الشكل الناتج:
-- ["adder"] = { "Adder", 0, "<img src='URL' width='300' height='300'/><br/> 0 : السعر <br/>" },
--
-- عند VehicleSource = 'garage' يُحفظ أيضاً ملف الجراج كاملاً بعد تعبئة
-- الصور الجديدة في Files/Data/garage.lua، جاهز لاستبدال ملفك الأصلي.
--
-- webhook        : رابط ويب هوك ديسكورد الخاص بالجراج (إذا فُرِّغ يستخدم DiscordWebHook).
-- garageName     : اسم الجراج المستخدم عند البناء من config/sql فقط.
-- defaultPrice   : السعر الافتراضي إذا لم يكن للسيارة سعر.
-- priceLabel     : الكلمة المعروضة بعد السعر داخل الوصف.
-- imgWidth/imgHeight : أبعاد الصورة داخل وسم img عند بناء سطر جديد.
-- sendEach       : يرسل سطر السيارة فور حفظ صورتها.
-- sendOnFinish   : يرسل النتيجة كاملة عند انتهاء جلسة التصوير.
-- saveFile       : يحفظ الناتج في Files/Data/garage.lua.
-- includeConfig  : يضيف سطر _config عند البناء من config/sql.
-- includeMissing : يضيف السيارات التي بدون صورة بوسم img فارغ.
-- vtype          : نوع المركبات المستخدم داخل _config.
ServerConfig.GarageExport = {
    enabled        = true,
    webhook        = '',
    garageName     = 'M5-garage',
    defaultPrice   = 0,
    priceLabel     = 'السعر',
    imgWidth       = 300,
    imgHeight      = 300,
    sendEach       = true,
    sendOnFinish   = true,
    saveFile       = true,
    includeConfig  = true,
    includeMissing = false,
    vtype          = 'car',
    configLine     = '{ markercolor = { 255, 255, 255, 255 }, blipid = 225, disableRent = false, blipcolor = 0, blipscale = 1.0, disableBuy = false, permissions = { "%GARAGE%.Cars" }, gname = "%GARAGE%", disableTransfer = false, markertype = 36, vtype = "%VTYPE%", disableSell = false, disableTest = false, MarkerImg = "garages" }',
}
