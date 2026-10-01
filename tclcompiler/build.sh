#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0a0'
url="https://github.com/tclmonster/tclcompiler2/archive/refs/tags/v${version}.tar.gz"
sha256='194c55fb1c7e40bae6b038de174ecd6ec4d6694a7dd9a57c1ef14b93a7a936a1'

KC_TCLCOMPILER_CFLAGS='-Wno-error=implicit-function-declaration'
configure_extra=(--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include)

# Tcl 9.1 changed the bytecode format; tclcompiler has not been ported yet
function predownload() {
	case "${TCL_VERSION}" in
		9.0|8.*)
			;;
		9.*)
			echo "tclcompiler does not support Tcl ${TCL_VERSION}" >&2
			return 1
			;;
	esac
}
