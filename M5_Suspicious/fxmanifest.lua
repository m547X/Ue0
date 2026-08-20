--[[ ============================================================
     M5_Suspicious  |  Manifest
     ============================================================ ]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'M5_Suspicious'
author      'M5'
description 'كشف اللاعبين المشبوهين + Risk Score + حظر HWID دائم  |  vRP 0.5 + oxmysql'
version     '2.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

client_scripts {
    'config_client.lua',
    'client.lua',
}

-- config_server.lua ليس shared عمداً: فيه الـ Salt والـ API Key والـ Webhooks.
server_scripts {
    '@vrp/lib/utils.lua',
    '@oxmysql/lib/MySQL.lua',
    'config_server.lua',
    'server.lua',
}

dependencies {
    'oxmysql',
    'vrp',
}
