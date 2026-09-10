fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'M5_RankedPvP'
author      'M5'
description 'M5 Ranked PvP — Competitive Ranked / MMR / Seasons / Custom Games'
version     '1.0.0'

ui_page 'Files/ui/index.html'

shared_scripts {
    'الاعدادات/Locale.lua',
    'الاعدادات/Export.lua'
}

client_scripts {
    'الاعدادات/Config_Client.lua',
    'Files/Client.lua'
}


server_scripts {
    '@vrp/lib/utils.lua',
    '@oxmysql/lib/MySQL.lua',
    'الاعدادات/Config_Server.lua',
    'Files/Server.lua'
}

files {
    'Files/ui/index.html',
    'Files/ui/style.css',
    'Files/ui/app.js',
    'Files/ui/img/*.png',
    'Files/ui/img/*.jpg',
    'Files/ui/img/*.webp'
}

dependencies {
    'vrp',
    'oxmysql'
}
