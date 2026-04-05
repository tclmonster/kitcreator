#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0a0'
url="https://github.com/tclmonster/tbcload2/archive/refs/tags/v${version}.tar.gz"
sha256='292537bca57ba60c43ae79e74811409e62d3f1c97da945b7f4b6b8950e7941e1'

KC_TBCLOAD_CFLAGS='-Wno-error=implicit-function-declaration'

function postinstall() {
	if [ "$KITTARGET" = "kitdll" ]; then
		cp -r "${installdir}/include" "${runtimedir}" || return 1
	fi
}
