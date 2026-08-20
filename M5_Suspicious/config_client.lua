--[[ ============================================================
     M5_Suspicious  |  Client Config
     ------------------------------------------------------------
     هذا الملف يُحمَّل عند كل لاعب، لذلك لا يحتوي إلا على إعدادات
     العرض فقط: اللغة، الألوان، مفتاح الفتح، والنصوص.
     لا يوجد هنا أي Webhook أو Salt أو API Key أو صلاحية —
     كلها في config_server.lua ولا تغادر السيرفر أبداً.
     ============================================================ ]]

Config = {}

-- ============================================================
--  اللغة  |  Language
-- ============================================================

-- "ar" أو "en" — الواجهة NUI فتدعم العربية و RTL بالكامل.
Config.Language = "ar"

-- اتجاه الواجهة: "auto" يختار rtl للعربية تلقائياً، أو أجبره بـ "rtl" / "ltr".
Config.Direction = "auto"

-- ============================================================
--  الفتح  |  Opening the panel
-- ============================================================

-- مفتاح اختياري لفتح اللوحة ("" لتعطيله). أمر /suspicious يعمل دائماً.
-- السيرفر يفحص الصلاحية قبل أن تُفتح اللوحة في كل الحالات.
Config.MenuKey = ""

-- عدد الصفوف في الصفحة الواحدة.
Config.MenuPageSize = 10

-- ============================================================
--  التنبيهات  |  Alerts
-- ============================================================

Config.Alert = {
    -- "top-right" | "top-left" | "bottom-right" | "bottom-left"
    Position = "top-right",
    -- صوت عند وصول تنبيه.
    Sound    = true,
}

-- ============================================================
--  الثيم  |  M5 Theme
-- ============================================================
-- أي قيمة هنا تُمرَّر إلى الـ CSS كمتغيّر بنفس الاسم.
-- استخدم HEX أو rgb() فقط.

Config.Theme = {
    ["bg"]        = "#0b0c10",
    ["surface"]   = "#14161d",
    ["surface-2"] = "#1b1e27",
    ["line"]      = "#262a36",
    ["text"]      = "#e8eaf0",
    ["muted"]     = "#8b90a0",

    -- لون M5 الأساسي والتدرّج الثانوي
    ["accent"]    = "#e5484d",
    ["accent-2"]  = "#ff8a3d",

    -- ألوان مستويات الخطورة
    ["low"]       = "#46c07a",
    ["medium"]    = "#e8c14a",
    ["high"]      = "#f08a3c",
    ["critical"]  = "#e5484d",
}

-- ============================================================
--  مدد الحظر  |  Ban duration labels
-- ============================================================
-- أسماء فقط. الكلاينت يرسل رقم الخيار، والسيرفر يقرأ المدة الحقيقية
-- من Config.BanDurations في config_server.lua.
-- حافظ على نفس الترتيب في الملفين.

Config.BanDurationLabels = {
    "دائم",
    "30 يوم",
    "7 أيام",
    "24 ساعة",
}

-- ============================================================
--  النصوص  |  Strings
-- ============================================================

Config.Locale = {
    ar = {
        -- التنبيه
        alert_title        = "لاعب مشبوه",
        alert_yes          = "نعم",
        alert_no           = "لا",
        alert_unknown      = "غير معروف",

        -- اللوحة
        menu_title         = "اللاعبون المشبوهون",
        menu_empty         = "اختر لاعباً من القائمة لعرض تفاصيله.",
        subtitle_records   = "سجل",
        search_placeholder = "بحث بالاسم أو الرقم...",

        -- الفلاتر
        filter_all         = "الكل",
        filter_pending     = "قيد المراجعة",
        filter_high        = "خطورة عالية",
        filter_critical    = "حرِج",
        filter_online      = "متصل",

        -- الأقسام
        section_reasons    = "أسباب الاشتباه",
        section_identity   = "المعلومات",

        -- الأزرار
        menu_ban_hwid      = "حظر HWID",
        menu_ban_license   = "حظر License",
        menu_ban_player    = "حظر اللاعب",
        menu_ignore        = "تجاهل",
        menu_refresh       = "تحديث",

        -- النافذة المنبثقة
        label_reason       = "سبب الحظر",
        label_duration     = "مدة الحظر",
        btn_cancel         = "إلغاء",
        btn_confirm        = "تأكيد الحظر",

        -- حقول التفاصيل
        row_server_id      = "رقم السيرفر",
        row_user_id        = "رقم المستخدم",
        row_vpn            = "VPN / بروكسي",
        row_new            = "حساب جديد",
        row_shared_ip      = "IP مشترك",
        row_shared_hwid    = "HWID مشترك",
        row_tokens         = "عدد التوكنات",
        row_ip             = "الآي بي",
        row_license        = "License",
        row_discord        = "ديسكورد",
        row_fivem          = "معرّف FiveM",
        row_steam          = "ستيم",
        row_location       = "الموقع",
        row_first_seen     = "أول رصد",
        row_status         = "الحالة",
        row_online         = "متصل الآن",
    },

    en = {
        alert_title        = "SUSPICIOUS",
        alert_yes          = "YES",
        alert_no           = "NO",
        alert_unknown      = "UNKNOWN",

        menu_title         = "Suspicious Players",
        menu_empty         = "Select a player from the list to see the details.",
        subtitle_records   = "records",
        search_placeholder = "Search by name or id...",

        filter_all         = "All",
        filter_pending     = "Pending",
        filter_high        = "High risk",
        filter_critical    = "Critical",
        filter_online      = "Online",

        section_reasons    = "DETECTION REASONS",
        section_identity   = "IDENTITY",

        menu_ban_hwid      = "Ban HWID",
        menu_ban_license   = "Ban License",
        menu_ban_player    = "Ban Player",
        menu_ignore        = "Ignore",
        menu_refresh       = "Refresh",

        label_reason       = "BAN REASON",
        label_duration     = "DURATION",
        btn_cancel         = "Cancel",
        btn_confirm        = "Confirm ban",

        row_server_id      = "Server ID",
        row_user_id        = "User ID",
        row_vpn            = "VPN / Proxy",
        row_new            = "New Account",
        row_shared_ip      = "Shared IP",
        row_shared_hwid    = "Shared HWID",
        row_tokens         = "HWID Tokens",
        row_ip             = "IP",
        row_license        = "License",
        row_discord        = "Discord",
        row_fivem          = "FiveM ID",
        row_steam          = "Steam",
        row_location       = "Location",
        row_first_seen     = "First Detected",
        row_status         = "Status",
        row_online         = "Online",
    },
}
