fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'm5_suspicious'
author 'm5'
description 'Suspicious player detection, risk scoring and permanent HWID bans for vRP 0.5 + oxmysql'
version '1.0.0'

-- The config is deliberately NOT a shared_script: config_server.lua holds the
-- HWID salt, the VPN API key and the Discord webhooks, and must never be
-- downloadable by a client.
client_scripts {
    'config_client.lua',
    'client.lua',
}

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
