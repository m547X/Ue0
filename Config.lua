--                                                                                                                                                 --
--                    ███╗░░░███╗░█████╗░██████╗░███████╗      ██████╗░██╗░░░██╗    ███╗░░░███╗███████╗                                            --
--                    ████╗░████║██╔══██╗██╔══██╗██╔════╝      ██╔══██╗╚██╗░██╔╝    ████╗░████║██╔════╝                                            --
--                    ██╔████╔██║███████║██║░░██║█████╗░░      ██████╦╝░╚████╔╝░    ██╔████╔██║██████╗░                                            --
--                    ██║╚██╔╝██║██╔══██║██║░░██║██╔══╝░░      ██╔══██╗░░╚██╔╝░░    ██║╚██╔╝██║╚════██╗                                            --
--                    ██║░╚═╝░██║██║░░██║██████╔╝███████╗      ██████╦╝░░░██║░░░    ██║░╚═╝░██║██████╔╝                                            --
--                    ╚═╝░░░░░╚═╝╚═╝░░╚═╝╚═════╝░╚══════╝      ╚═════╝░░░░╚═╝░░░    ╚═╝░░░░░╚═╝╚═════╝░                                            --
--                                                                                                                                                 --
--                                                       M5_iCreator | نظام تصوير المركبات                                                     --
--                                                           السكربت غير مجاني                                                                    --
--                                                              Made By M547                                                                       --
--                                                         https://discord.gg/MUS                                                                  --

Config = {}
-- >> ================================================[اعدادات سيرفرك]================================================= << --
Config.License = "" -- >> [ رخصة السكربت ]



-- >> ================================================[ اعدادات  السكربت ]================================================= << --

-- فعّل هذه الخيارات إذا احتجت تشخيص مشاكل السكربت.
-- server: يطبع رسائل تتبع في كونسول السيرفر.
-- client: يطبع رسائل تتبع في كونسول اللاعب.
Config.Debug = {
    server = false,
    client = false,
}

-- ⚠️ الإعدادات الحساسة انتقلت إلى ملف ServerConfig.lua الذي يعمل في السيرفر فقط:
--    طريقة الحفظ (json/kvp/api)، روابط وتوكن الـ API، توكن GitHub،
--    روابط الويب هوك، مصدر السيارات ومسار ملف الجراج، وإعدادات جدول الجراج.
--    هذا الملف (Config.lua) مشترك ويصل للاعبين، فلا تضع فيه أي توكن.

-- ─── Image Host ──────────────────────────────────────────────
-- مكان رفع صور السيارات:
-- fivemanage : يرفع الصورة من اللاعب مباشرة إلى FiveManage (يحتاج Config.FiveManagerToken).
-- github     : يلتقط الصورة عند اللاعب ثم يرفعها السيرفر إلى مستودع GitHub،
--              وهو الخيار الآمن لأن التوكن يبقى في ServerConfig.lua.
Config.ImageHost = 'fivemanage'         -- 'fivemanage' | 'github'

-- ─── Capture ─────────────────────────────────────────────────
-- إعدادات التقاط الصورة عند اللاعب (تُستخدم مع ImageHost = 'github').
-- encoding  : صيغة الصورة، jpg أصغر حجماً من png.
-- quality   : جودة الصورة من 0.1 إلى 1.0.
-- chunkSize : حجم كل جزء يُرسل من اللاعب إلى السيرفر، لا ترفعه كثيراً.
Config.Capture = {
    encoding  = 'jpg',                  -- 'jpg' | 'png' | 'webp'
    quality   = 0.90,
    chunkSize = 40000,
}

-- ─── Vehicle Source ──────────────────────────────────────────
-- فلترة السيارات حسب التصنيف عند السحب من قاعدة البيانات أو من الجدول الاحتياطي.
-- all يعرض كل السيارات، ويمكن استخدام تصنيفات مثل super أو sports.
-- ⚠️ لا تؤثر على السحب من ملف الجراج (ServerConfig.VehicleSource = 'garage').
Config.Category       = 'all'           -- 'all' | 'super' | 'sports' | ...

-- قائمة السيارات الاحتياطية المستخدمة إذا لم يتم جلب السيارات من قاعدة البيانات.
-- model هو اسم السبون، name هو الاسم المعروض، category هو التصنيف المستخدم مع Config.Category.
-- price اختياري ويُستخدم في جدول الجراج.
Config.SqlVehicleTable = {
    { model = 'adder',    name = 'Adder',     category = 'super', price = 0 },
    { model = 'zentorno', name = 'Zentorno',  category = 'super', price = 0 },
    { model = 't20',      name = 'T20',       category = 'super', price = 0 },
    { model = 'entityxf', name = 'Entity XF', category = 'super', price = 0 },
    { model = 'osiris',   name = 'Osiris',    category = 'super', price = 0 },
}

-- ─── Access ───────────────────────────────────────────────────
-- نظام الصلاحيات:
-- vrp    : يستخدم صلاحية vRP الموجودة في Config.vRPPermission.
-- owners : يسمح فقط للمعرفات الموجودة في Config.owners.
Config.PermissionMode = 'vrp'       -- 'vrp' | 'owners'

-- صلاحية vRP المطلوبة عند استخدام PermissionMode = 'vrp'.
Config.vRPPermission  = 'player.phone'

-- قائمة المالكين عند استخدام PermissionMode = 'owners'.
-- أضف license أو steam أو أي identifier كامل للاعب واجعل قيمته true.
Config.owners = {
    ['license:abf9e8175db7e0b63e5dd765682c1390a6b5d5b5'] = true,
    -- ['steam:1100001xxxxxxxx'] = true,
}

-- ─── FiveManage API ──────────────────────────────────────────
-- توكن FiveManage المستخدم لرفع الصور عبر screenshot-basic.
-- يجب تعبئته حتى تعمل عملية رفع الصور عند ImageHost = 'fivemanage'.
-- ملاحظة أمان: هذا التوكن يصل للاعبين لأن الرفع يتم من جهازهم،
-- لذلك استخدم توكن مخصص للصور فقط، أو استخدم ImageHost = 'github'
-- حيث يبقى التوكن داخل السيرفر في ServerConfig.lua.
Config.FiveManagerToken  = ''

-- مدة الانتظار بالمللي ثانية بعد سبون السيارة وقبل التقاط الصورة.
-- زِد القيمة إذا كانت السيارات أو الخامات تتأخر في التحميل.
Config.ScreenshotDelay   = 2000         -- ms to wait before screenshot

-- السيارة الافتراضية المستخدمة في المعاينة ومحررات المواقع.
Config.DefaultTestVehicle = 'adder'

-- إخفاء شخصية اللاعب أثناء التصوير حتى لا تظهر داخل الصورة.
-- اجعلها false إذا أردت إبقاء اللاعب ظاهراً.
Config.HidePlayerDuringScreenshot = true

-- تخطي السيارات التي سبق حفظ صورتها في thumbnails.
-- اجعلها true لتجنب إعادة تصوير السيارات الموجودة مسبقاً.
-- ملاحظة: عند السحب من ملف الجراج يتم التخطي تلقائياً حسب
-- ServerConfig.GarageFile.onlyMissingImages.
Config.SkipCapturedVehicles = false

-- ─── Commands ────────────────────────────────────────────────
-- أسماء الأوامر داخل اللعبة.
-- ui يفتح الواجهة، start يبدأ التصوير، reset يعيد عداد التصوير،
-- getcoords يطبع الإحداثيات، getperms يحدّث صلاحية اللاعب،
-- export يرسل جدول الجراج إلى الويب هوك (يعمل من كونسول السيرفر أيضاً)،
-- reload يعيد قراءة ملف الجراج / قاعدة البيانات،
-- check يطبع تشخيصاً كاملاً لقراءة ملف الجراج في كونسول السيرفر.
Config.Commands = {
    ui           = 'vshot',
    start        = 'startscreenshot',
    reset        = 'resetscreenshot',
    getcoords    = 'getcoords',
    getperms     = 'getperms',
    export       = 'exportgarage',
    reload       = 'reloadvehicles',
    check        = 'garagecheck',
}

-- ─── Camera Editor Settings ──────────────────────────────────
-- إعدادات محرر الكاميرا داخل اللعبة:
-- moveSpeed سرعة الحركة العادية.
-- fastMoveSpeed سرعة الحركة عند الضغط على Shift.
-- rotateSpeed حساسية دوران الكاميرا بالماوس.
-- fovMin و fovMax حدود الزوم.
-- fovStep مقدار تغير الزوم مع عجلة الماوس.
Config.CameraEditor = {
    moveSpeed      = 0.25,
    fastMoveSpeed  = 1.20,
    rotateSpeed    = 4.0,
    fovMin         = 5.0,
    fovMax         = 100.0,
    fovStep        = 2.0,
}


Config.DefaultSpots = {
    -- ── Arena Workshop ────────────────────────────────────────
    {
        -- id معرف فريد للمكان، وname الاسم المعروض في الواجهة.
        id    = 'arena_default',
        name  = 'Arena Studio',

        -- قائمة IPLs التي يتم تحميلها لهذا المكان.
        ipl = {
            'xs_arena_interior',
            'xs_arena_interior_vip',
            'xs_arena_banners_ipl',
        },

        -- إعدادات الانتريور والبروبس المطلوب تفعيلها.
        interiorCoords = { x = 2800.0, y = -3800.0, z = 100.0 },
        interiorProps  = { 'Set_Crowd_A', 'Set_Crowd_B', 'Set_Crowd_C', 'Set_Crowd_D' },

        -- مكان انتقال اللاعب عند تجهيز موقع التصوير.
        playerCoords  = { x = 2800.5966, y = -3799.7370, z = 139.4151, w = 244.5432 },

        -- مكان وضع السيارة واتجاهها أثناء التصوير.
        vehicleCoords = { x = 2800.5966, y = -3799.7370, z = 139.4151, w = 80.117 },

        -- إعدادات الكاميرا: الموقع، الدوران، وزاوية الرؤية FOV.
        camera = {
            pos = { x = 2796.5966, y = -3803.7370, z = 140.9514 },
            rot = { x = -15.0, y = 0.0, z = 252.063 },
            fov = 42.0,
        },

        -- إعدادات الإضاءة حول السيارة.
        light = {
            pos       = { x = 2796.5966, y = -3796.7370, z = 142.5 },
            color     = { r = 255, g = 245, b = 220 },
            range     = 45.0,
            intensity = 18.0,
        },

        -- أجواء التصوير: الطقس ووقت الساعة داخل اللعبة.
        weather    = 'EXTRASUNNY',
        timeHour   = 12,
        timeMin    = 0,

        -- دوران السيارة تلقائياً أثناء التصوير وسرعة الدوران.
        autoRotate  = false,
        rotateSpeed = 0.4,

        -- يمنع حذف هذا المكان من الواجهة إذا كانت القيمة true.
        isDefault = true,
    },

}
