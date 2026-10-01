#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0a0'
url="https://github.com/tclmonster/tbcload2/archive/refs/tags/v${version}.tar.gz"
sha256='ecc72947288cdc98833a75711596ee20b54ae6897a2286acd7def39b73224291'

KC_TBCLOAD_CFLAGS='-Wno-error=implicit-function-declaration'

# Tcl 9.1 changed the bytecode format; tbcload has not been ported yet
function predownload() {
	case "${TCL_VERSION}" in
		9.0|8.*)
			;;
		9.*)
			echo "tbcload does not support Tcl ${TCL_VERSION}" >&2
			return 1
			;;
	esac
}

function postinstall() {
	if [ "$KITTARGET" = "kitdll" ]; then
		cp -r "${installdir}/include" "${runtimedir}" || return 1
	fi
}
