#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.7.1'
url="https://github.com/bandoti/tclcompiler/archive/refs/tags/v${version}.tar.gz"
sha256='2c30c6d10e46940d3a61c5ab46aa7ecbfe9745b1f0860bcd7b3236ef643f6e49'

configure_extra="--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include"

function prebuild() {
	local tbcload_headers="$(ls ${KITCREATOR_DIR}/tbcload/inst/include/*.h 2>/dev/null)"

	if [ -z "$tbcload_headers" ]; then
		echo "Error: tbcload must be built prior to tclcompiler"
		return 1
	fi

	for h in $tbcload_headers; do
		cp $h $workdir || return 1
	done
}
