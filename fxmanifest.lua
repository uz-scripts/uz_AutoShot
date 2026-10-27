fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'uz_AutoShot'
description 'Clothing Thumbnail Generator & Browser for FiveM'
author 'UZ'
version '2.3.0'
repository 'https://github.com/uz-scripts/uz_AutoShot'

shared_scripts {
    'Customize.lua',
}

client_scripts {
    'client/client.lua',
}

server_scripts {
    'server/version.lua',
    'server/config_bridge.lua',
    'server/server.js',
}

ui_page 'resources/build/index.html'

files {
    'resources/build/index.html',
    'resources/build/**/*',
    'shots/**/*',
}

dependencies {
	'screenshot-basic',
    'yarn'
}
