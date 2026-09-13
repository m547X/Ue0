# M5_iCreator — التحديثات الجديدة

ثلاث إضافات:

1. **خيار حفظ الصور عبر API** (بما فيه رفع الصور إلى **GitHub**).
2. **ويب هوك يرسل سطر الجراج جاهزاً للنسخ** مع الصورة واسم السيارة والسعر.
3. **سحب السيارات من ملف الجراج نفسه** وتصوير **الفاضية فقط**.

كل الإعدادات الحساسة (التوكنات، روابط الـ API، الويب هوك، مسار ملف الجراج)
في `ServerConfig.lua` وهو ملف **يعمل في السيرفر فقط** ولا يصل للاعبين.

---

## هيكل الملفات

```
M5_iCreator/
├── fxmanifest.lua
├── Config.lua              ← مشترك (لا تضع فيه أي توكن)
├── ServerConfig.lua        ← سيرفر فقط (التوكنات والمسارات)
└── Files/
    ├── Client.lua
    ├── Server.lua
    ├── Data/
    │   ├── thumbnails.json
    │   ├── spots.json
    │   └── garage.lua      ← يُنشأ تلقائياً عند التصدير
    └── html/
        ├── index.html
        ├── style.css
        └── app.js
```

`ServerConfig.lua` مضاف أصلاً في `fxmanifest.lua` داخل `server_scripts` قبل `Server.lua`.
**لا تضعه أبداً** في `client_scripts` أو `shared_scripts`.

---

## 1) سحب السيارات من ملف الجراج

الميزة الأساسية: السكربت يقرأ ملف الجراج، يأخذ السيارات التي وسم الصورة فيها فارغ
(`<img src='' ... />`) ويتجاهل التي لها صورة، ثم بعد التصوير يعيد بناء نفس الملف
بالصور الجديدة.

```lua
-- ServerConfig.lua
ServerConfig.VehicleSource = 'garage'

ServerConfig.GarageFile = {
    resource          = 'vrp',              -- الريسورس الذي فيه الملف
    path              = 'cfg/garages.lua',  -- المسار داخله
    garages           = {},                 -- {} = كل الجراجات
    skipGarages       = {},                 -- جراجات تُستثنى
    onlyMissingImages = true,               -- الفاضية فقط
    skipSaved         = true,               -- تخطي المصوّرة مسبقاً
    overwriteExisting = false,              -- عند التصدير: لا يلمس الروابط الموجودة
}
```

المسار أعلاه يقرأ: `resources/[vrp]/vrp/cfg/garages.lua`

### لتصوير جراجات محددة فقط

```lua
garages = { "Sonic-garage", "cut-OFF", "كراج الضرب" },
```

### ما يفهمه القارئ

- يقرأ `cfg.garage_types` ويتجاهل `cfg.garages` (قائمة الإحداثيات) و `_config`.
- يدعم صيغتي كتابة السطر:
  - `["model"] = { "name", 0, "<img .../>" },`
  - `["model"] = {"name", 0, "<img .../>", },`  (بفاصلة بعد الوصف)
- لو كان الوصف فارغاً تماماً (`""`) أو بدون وسم `<img>`، يضيف الوسم في بداية
  الوصف مع الحفاظ على باقي النص (السرعة، المقاعد، التقييم… إلخ).
- أسماء الجراجات بالعربي والإنجليزي والأرقام (`"600"`, `"141-Helicopters"`, `"كراج الضرب"`).
- كل أشكال وسم الصورة:
  - `<img src='' width='300' .../>`
  - `<img width='360' height='240' src=''/>`
  - `<img src='https://...'width='300'...` (بدون مسافة)
  - الأوسمة الناقصة أو المكسورة.
- **السيارة المكررة في أكثر من جراج تُصوَّر مرة واحدة**، ثم يُعبّأ رابطها
  في كل الجراجات التي تحتويها عند التصدير.

### الناتج

بعد انتهاء الجلسة يُحفظ الملف كاملاً في `Files/Data/garage.lua` — نفس ملفك الأصلي
حرفياً مع تعبئة `src=''` فقط. انسخه فوق ملف الجراج الأصلي بعد مراجعته.

الأوامر:

```
/garagecheck       -- تشخيص: يطبع من أين قرأ الملف وكم جراج وكم سيارة
/exportgarage      -- تصدير في أي وقت (من اللعبة أو كونسول السيرفر)
/reloadvehicles    -- إعادة قراءة ملف الجراج بدون ريستارت
```

### إذا لم يقرأ الملف

شغّل `/garagecheck` من كونسول السيرفر، سيطبع لك:
حالة الريسورس، مجلده الفعلي على القرص، المسار الذي نجحت القراءة منه،
عدد الجراجات والسيارات، وإذا فشل يطبع كل المسارات التي جرّبها.

نقاط مهمة:

- `resource` هو **اسم مجلد الريسورس نفسه** وليس المجلد الذي يحويه.
  لو كان الملف في `resources\[Danger_Main]\Danger_Garages\Garages.lua` فالإعداد:

  ```lua
  resource = 'Danger_Garages',
  path     = 'Garages.lua',
  ```

- `path` نسبي **داخل** الريسورس. لو الملف داخل مجلد فرعي اكتبه كاملاً:
  `path = 'config/Garages.lua'`.
- على لينكس أسماء الملفات حساسة لحالة الأحرف. السكربت يجرّب تلقائياً
  الأسماء والمجلدات الشائعة (`Garages.lua`، `garages.lua`، `cfg/`، `config/`، …)
  وينبّهك في الكونسول بالمسار الصحيح إذا وجده في مكان مختلف.
- إذا قرأ الملف لكن لم يجد أي سيارة، يطبع أول 15 سطر من الملف حتى ترى
  الشكل الفعلي للأسطر. الشكل المتوقع:
  `["model"] = { "name", 0, "<img src='' .../>" },`

وفي الواجهة، تبويب **التصوير** فيه بطاقة "مصدر السيارات" تعرض المصدر والإجمالي
وعدد السيارات بدون صورة، مع زري إعادة القراءة والتصدير.

---

## 2) حفظ الصور عبر API

```lua
ServerConfig.save = 'json'   -- 'json' | 'kvp' | 'api'
```

عند اختيار `api`:

```lua
ServerConfig.SaveAPI = {
    saveUrl      = 'https://example.com/api/thumbnails',
    loadUrl      = 'https://example.com/api/thumbnails',  -- اختياري (GET عند التشغيل)
    method       = 'POST',
    headers      = { ['Authorization'] = 'Bearer xxxxx' },
    perVehicle   = true,   -- يرسل كل سيارة لحظة تصويرها
    mirrorToFile = true,   -- نسخة احتياطية في thumbnails.json
}
```

شكل الطلب عند `perVehicle = true`:

```json
{
  "resource": "M5_iCreator",
  "model": "GX2002QA",
  "name": "sonic3",
  "price": 0,
  "garage": "Sonic-garage",
  "url": "https://.../GX2002QA.jpg",
  "savedAt": 1765432100
}
```

وعند `false` يُرسل الجدول كاملاً في الحقل `thumbnails`.
أما `loadUrl` فيقبل: `{...}` أو `{ "thumbnails": {...} }` أو `{ "data": {...} }`.

---

## 3) رفع الصور إلى GitHub

الصورة تُلتقط عند اللاعب، تُرسل للسيرفر على أجزاء، والسيرفر يرفعها عبر
GitHub Contents API. **التوكن لا يخرج من السيرفر إطلاقاً.**

```lua
-- Config.lua (مشترك)
Config.ImageHost = 'github'
Config.Capture   = { encoding = 'jpg', quality = 0.90, chunkSize = 40000 }
```

```lua
-- ServerConfig.lua (سيرفر فقط)
ServerConfig.GitHub = {
    token   = '',                 -- الأفضل استخدام الكونفار بالأسفل
    owner   = 'YourName',
    repo    = 'vehicle-images',
    branch  = 'main',
    path    = 'vehicles',
    urlMode = 'raw',              -- raw | cdn | download
}
```

في `server.cfg` (الطريقة الآمنة للتوكن):

```cfg
set m5_github_token "github_pat_xxxxxxxxxxxxxxxx"
```

التوكن يحتاج صلاحية **Contents: Read and write** على المستودع فقط،
والمستودع يجب أن يكون **Public** حتى تظهر الصور داخل اللعبة.

| urlMode | الرابط الناتج |
|---------|----------------|
| `raw` | `https://raw.githubusercontent.com/owner/repo/branch/vehicles/adder.jpg` |
| `cdn` | `https://cdn.jsdelivr.net/gh/owner/repo@branch/vehicles/adder.jpg` |
| `download` | الرابط الذي يرجعه GitHub في رد الـ API |

> `Config.ImageHost = 'fivemanage'` (الافتراضي) يبقى يعمل كما كان. توكن FiveManage
> يصل للاعب لأن الرفع من جهازه، لذلك `github` هو الخيار الآمن.

---

## 4) ويب هوك الجراج

بعد تصوير كل سيارة يصل سطر جاهز للنسخ مع صورة السيارة واسمها وسعرها واسم جراجها:

```lua
["GX2002QA"] = { "sonic3", 0, "<img src='https://raw.githubusercontent.com/.../GX2002QA.jpg' width='300' height='300'/><br/> 0 : السعر <br/>" },
```

وبعد انتهاء الجلسة تصل الأسطر المحدّثة مجمّعة حسب الجراج
(مقسّمة على رسائل بسبب حد 2000 حرف في ديسكورد):

```lua
["Sonic-garage"] = {
    ["GX2002QA"] = { "sonic3", 0, "<img src='...' width='300' height='300'/><br/> 0 : السعر <br/>" },
    ["SNCSTND"] = { "sonic1", 0, "<img src='...' width='300' height='300'/><br/> 0 : السعر <br/>" },
},
```

```lua
ServerConfig.GarageExport = {
    enabled      = true,
    webhook      = 'https://discord.com/api/webhooks/xxx/yyy',
    priceLabel   = 'السعر',
    imgWidth     = 300,
    imgHeight    = 300,
    sendEach     = true,   -- سطر بعد كل سيارة
    sendOnFinish = true,   -- الناتج كاملاً بعد انتهاء الجلسة
    saveFile     = true,   -- نسخة في Files/Data/garage.lua
}
```

إذا كان `webhook` فارغاً يستخدم `ServerConfig.DiscordWebHook`.
عند المصدر `config` أو `sql` يبني جدول جراج جديد باسم `garageName` مع سطر `_config`.

---

## Exports

```lua
exports['M5_iCreator']:BuildGarageTable()   -- نص الجدول / الملف المحدّث
exports['M5_iCreator']:ExportGarage()       -- يصدّر ويرجع عدد السيارات
exports['M5_iCreator']:ReloadVehicles()     -- يعيد القراءة ويرجع العدد
exports['M5_iCreator']:GetVehicleThumbnail('GX2002QA')
exports['M5_iCreator']:GetAllThumbnails()
```

---

## طريقة العمل المقترحة

1. `ServerConfig.VehicleSource = 'garage'` مع مسار ملف الجراج.
2. `Config.ImageHost = 'github'` + التوكن في `server.cfg`.
3. `/reloadvehicles` ثم افتح `/vshot` وشوف كم سيارة بدون صورة.
4. حدد مكان التصوير واضغط "ابدأ جلسة التصوير".
   للإيقاف اضغط **Backspace** (أو ESC) في أي لحظة — يعمل فوراً حتى أثناء
   انتظار التقاط الصورة، والسيارة التي لم تُصوَّر لا تُحتسب في العداد.
5. بعد الانتهاء: الأسطر تصل للويب هوك، والملف كامل في `Files/Data/garage.lua`.
