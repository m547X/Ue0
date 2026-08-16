--[[
    ============================================================================
     M5 Ranked PvP  —  Competitive PvP System for FiveM
    ----------------------------------------------------------------------------
     Framework : vRP  |  Database : oxmysql  |  UI : NUI (HTML/CSS/JS)
     Structure : Four system files, none of which you need to edit:
                    Config_Client.lua
                    Config_Server.lua
                    Files/Client.lua
                    Files/Server.lua
                 Plus one file that is yours:
                    Export.lua        your hooks, events and exports
    ============================================================================
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'M5_RankedPvP'
author      'M5'
description 'M5 Ranked PvP — Competitive Ranked / MMR / Seasons / Custom Games'
version     '1.0.0'

ui_page 'Files/ui/index.html'

-- Your integration hooks. Loaded on both sides so M5.Client and M5.Server can
-- live in one file; it holds no settings and no secrets.
shared_script 'Export.lua'

-- Client side only. Config_Server.lua is deliberately NOT listed here.
client_scripts {
    'Config_Client.lua',
    'Files/Client.lua'
}

-- Server side only. Config_Server.lua never reaches the client.
server_scripts {
    '@vrp/lib/utils.lua',
    '@oxmysql/lib/MySQL.lua',
    'Config_Server.lua',
    'Files/Server.lua'
}

files {
    'Files/ui/index.html',
    'Files/ui/style.css',
    'Files/ui/app.js'
}

dependencies {
    'vrp',
    'oxmysql'
}
