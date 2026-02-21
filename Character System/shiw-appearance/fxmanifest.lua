fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

description 'Character System by Shiw Magic Script'
version '3.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/functions.lua',
    'shared/starter_clothing.lua',
}

client_scripts {
    'client/load_functions.lua',
    'client/hashtocache.lua',
    'client/naked_body.lua',    -- ★ НОВОЕ: Система голого тела (ПЕРЕД creator и clothes!)
    'client/creator.lua',
    'client/clothes.lua',
    'client/html_ui.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_appearance.lua',
    'server/sv_clothing.lua',
    'server/versionchecker.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'img/*.png',
    'data/features.lua',
    'data/overlays.lua',
    'data/clothing.lua',
    'data/hairs_list.lua',
    'data/clothes_list.lua',
    'locales/*.json',
    'locales/*.lua',
}

ox_libs {
    'locale',
}

dependencies {
    'rsg-core',
    'ox_lib',
    'rsg-menubase'
}