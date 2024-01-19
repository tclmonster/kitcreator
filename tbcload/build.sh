#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.7'
url="https://github.com/bandoti/tbcload/archive/refs/tags/v${version}.tar.gz"
sha256='a1cbfdb0e3e61e08b996df713dd210a6103a7828650aa39630355cecd1c24b63'

KC_TBCLOAD_CFLAGS='-Wno-error=implicit-function-declaration'

function postinstall() {
	if [ "$KITTARGET" = "kitdll" ]; then
		cp -r "${installdir}/include" "${runtimedir}" || return 1
	fi
}
