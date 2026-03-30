fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'uz_AutoShot'
description 'Clothing Thumbnail Generator & Browser for FiveM'
author 'UZ'
version '1.1.1'
repository 'https://uz-scripts.com/scripts/uz-autoshot'

shared_scripts {
    'Customize.lua',
}

client_scripts {
    'client/client.lua',
}

server_scripts {
    'server/version.lua',
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