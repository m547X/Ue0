

fx_version 'cerulean'
games { 'gta5' }

description 'M5_iCreator - Professional Vehicle Screenshot System'
version '2.0.0'
author 'M5_iCreator'

server_scripts {
    '@mysql-async/lib/MySQL.lua',
    '@vrp/lib/utils.lua',
    'Config.lua',
    'ServerConfig.lua',
    'Files/Server.lua',
}

client_scripts {
    'Config.lua',
    'Files/Client.lua',
}

ui_page 'Files/html/index.html'

files {
    'Files/html/index.html',
    'Files/html/style.css',
    'Files/html/app.js',
    'Files/Data/spots.json',
    'Files/Data/thumbnails.json',
}

dependency 'vrp'
dependency 'screenshot-basic'
