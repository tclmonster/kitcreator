#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0a0'
url="https://github.com/tclmonster/tbcload2/archive/refs/tags/v${version}.tar.gz"
sha256='ecc72947288cdc98833a75711596ee20b54ae6897a2286acd7def39b73224291'

KC_TBCLOAD_CFLAGS='-Wno-error=implicit-function-declaration'

function postinstall() {
	if [ "$KITTARGET" = "kitdll" ]; then
		cp -r "${installdir}/include" "${runtimedir}" || return 1
	fi
}
