fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'DG-Scripts'
description 'Realistic AI water rescue with lifeguard boat, beach handoff, CPR, and optional framework billing support.'
version '2.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/utils.lua',
    'client/framework.lua',
    'client/routing.lua',
    'client/rescue.lua',
    'client/main.lua'
}

server_scripts {
    'server/version_check.lua',
    'server/main.lua'
}
