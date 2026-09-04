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
                 Plus two files that are yours:
                    Locale.lua        every line of text the players see
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

-- Every user-facing line, and your integration hooks. Both are loaded on the
-- client and the server; neither holds settings or secrets.
shared_scripts {
    'Locale.lua',
    'Export.lua'
}

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
    'Files/ui/app.js',
    -- Artwork you drop in: map previews, store cards, weapon renders. The
    -- folder may be empty; every one of them has a drawn fallback.
    'Files/ui/img/*.png',
    'Files/ui/img/*.jpg',
    'Files/ui/img/*.webp'
}

dependencies {
    'vrp',
    'oxmysql'
}
