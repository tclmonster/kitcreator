#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.7.1'
url="https://github.com/bandoti/tclcompiler/archive/refs/tags/v${version}.tar.gz"
sha256='ad11c9a9cce3c59a3168fc24d5ef29f071bc98aa2b4b8e3015a9c917fdc828f3'

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
