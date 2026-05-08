#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0'
url="http://sourceforge.net/projects/tcllib/files/tcllib/${version}/tcllib-${version}.tar.bz2"
sha256='196c574da9218cf8dcf180f38a603e670775ddb29f191960d6f6f13f52e56b04'

stagingdir="${pkgdir}/staging"

function clean() {
	rm -rf "${installdir}" "${runtimedir}" "${stagingdir}"
}

function configure() {
	local prefix

	KC_TCLLIB_PKGS="${KC_TCLLIB_PKGS:-all}"

	if [ "${KC_TCLLIB_PKGS}" != "all" ]; then
		rm -rf "${stagingdir}"
		mkdir -p "${stagingdir}" || return 1
		prefix="${stagingdir}"
	else
		prefix="${installdir}"
	fi

	./configure --prefix="${prefix}" --exec-prefix="${prefix}" --libdir="${prefix}/lib" \
		--with-tcl="${TCLCONFIGDIR}" || return 1
}

function build() {
	:
}

function install() {
	local tcllib_pkg tcllib_subdir tcllib_dirname

	KC_TCLLIB_PKGS="${KC_TCLLIB_PKGS:-all}"

	if [ "${KC_TCLLIB_PKGS}" = "all" ]; then
		${MAKE:-make} tcllibdir="${installdir}/lib" TCL_PACKAGE_PATH="${installdir}/lib" \
			install-tcl || return 1
	else
		${MAKE:-make} tcllibdir="${stagingdir}/lib" TCL_PACKAGE_PATH="${stagingdir}/lib" \
			install-tcl || return 1

		tcllib_subdir="$(ls -d "${stagingdir}/lib"/tcllib* 2>/dev/null | head -n 1)"
		if [ -z "${tcllib_subdir}" ]; then
			echo "Error: Could not find tcllib directory in staging area" >&2
			return 1
		fi

		tcllib_dirname="$(basename "${tcllib_subdir}")"
		mkdir -p "${installdir}/lib/${tcllib_dirname}" || return 1

		for tcllib_pkg in ${KC_TCLLIB_PKGS}; do
			if [ ! -d "${tcllib_subdir}/${tcllib_pkg}" ]; then
				echo "Error: tcllib package '${tcllib_pkg}' not found" >&2
				return 1
			fi
			cp -r "${tcllib_subdir}/${tcllib_pkg}" "${installdir}/lib/${tcllib_dirname}/" || return 1
		done

		sed "s|@KC_TCLLIB_PKGS@|${KC_TCLLIB_PKGS}|" "${pkgdir}/pkgIndex.tcl.in" \
			> "${installdir}/lib/${tcllib_dirname}/pkgIndex.tcl" || return 1
	fi
}
