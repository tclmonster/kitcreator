#! /usr/bin/env bash

# BuildCompatible: KitCreator


# Version here ensures the proper pkgIndex version
version='0.3.4'

tag_version='0.3.4.3'
url="https://github.com/RubyLane/parse_args.git"

# Cannot extract versions higher than 0.3.4.3 due to missing
# submodule files from tar.gz. As a workaround, clone with git.

function download() {
	mkdir "${archivedir}" >/dev/null 2>/dev/null
	git clone -b v${tag_version} --depth 1 --recurse-submodules \
		${url} "${archivedir}/parse_args" || return 1
}

function extract() {
	mkdir -p "${workdir}" || return 1
	( cd "${workdir}";
	  cp -rf "${archivedir}"/parse_args/* $(pwd);
	  autoreconf; )
}

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
