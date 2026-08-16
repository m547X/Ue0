fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'm5_suspicious'
author 'm5'
description 'Suspicious player detection, risk scoring and permanent HWID bans for vRP 0.5 + oxmysql'
version '1.0.0'

shared_script 'config.lua'

client_script 'client.lua'

server_scripts {
    '@vrp/lib/utils.lua',
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies {
    'oxmysql',
    'vrp',
}
