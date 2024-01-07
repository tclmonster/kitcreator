#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.7.1'
url="https://github.com/bandoti/tclcompiler/archive/refs/tags/v${version}.tar.gz"
sha256='1b652b6917f9e8e3fb77cb313de3edef381808b2fd2e000aa53ff73650c231e5'

configure_extra=(--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include)

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
