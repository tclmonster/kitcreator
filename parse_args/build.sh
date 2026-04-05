#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="0.5.2"
url="https://github.com/tclmonster/parse_args/releases/download/v${version}/parse_args${version}.tar.gz"
sha256='54d9ce25045f464fe3c96378490b5a9308726b3f2c5e7839fbd0dd7272b639f3'

function build() {
	# Skip docs because it requires pandoc
	${MAKE:-make} tcllibdir="${installdir}/lib" binaries libraries
}

# Copied from common.sh but skip installing docs
function install() {
	local filename newFilename

	mkdir -p "${installdir}/lib" || return 1
	${MAKE:-make} tcllibdir="${installdir}/lib" TCL_PACKAGE_PATH="${installdir}/lib" \
		install-binaries install-libraries || return 1

	# Rename ".LIB" files to ".a" files which KitCreator expects elsewhere
	find "${installdir}/lib" -type f -iname '*.lib' -o -iname '*.lib.linkadd' | while IFS='' read -r filename; do
		case "${filename}" in
			*.[Dd][Ll][Ll].[Ll][Ii][Bb])
				continue
				;;
		esac
		newFilename="$(echo "${filename}" | sed 's@\.lib$@.a@i;s@\.lib\.linkadd$@.a.linkadd@')"
		mv "${filename}" "${newFilename}"
	done
}
