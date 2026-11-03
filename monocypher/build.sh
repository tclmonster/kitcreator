#! /usr/bin/env bash

# BuildCompatible: KitCreator

# Monocypher (https://monocypher.org) with the Tcl binding in tclsrc/.
# Monocypher has no configure script, so configure, build and install compile
# it directly.  The binding is not in buildsrc/: common.sh copies buildsrc/
# instead of extracting the download.

version='4.0.3'
url="https://github.com/LoupVaillant/Monocypher/releases/download/${version}/monocypher-${version}.tar.gz"
sha256='8cc9bc341a66249016db9bd70e9142d8d0aef9945973744b1ac05dbc55d8ee66'

tclpkgversion='1.0'

function init_kitcreator() {
	pkg_always_static='1'
}

function preconfigure() {
	cp "${pkgdir}/tclsrc"/* . || return 1
}

# Defines MONOCYPHER_HAVE_GETENTROPY if the C library has getentropy();
# otherwise the binding reads /dev/urandom (Windows uses BCryptGenRandom)
function have_getentropy() {
	local test_program

	test_program='conftest-getentropy.c'
	cat << '_EOF_' > "${test_program}"
#include <unistd.h>
#if defined(__APPLE__) || defined(__linux__)
#include <sys/random.h>
#endif
int main(void) { unsigned char b[16]; return getentropy(b, sizeof(b)); }
_EOF_

	${CC:-cc} ${CPPFLAGS} ${CFLAGS} "${test_program}" -o conftest-getentropy >/dev/null 2>&1
}

function configure() {
	local base_var kc_var

	pkg_configure_shared_build='0'

	for base_var in CFLAGS CPPFLAGS LDFLAGS LIBS; do
		kc_var="KC_MONOCYPHER_${base_var}"
		if [ -n "${!kc_var}" ]; then
			eval "${base_var}=\"\${${base_var}} \${${kc_var}}\""
		fi
	done

	# Linked into a shared object for KitDLL
	if [ "${KITTARGET}" = 'kitdll' ]; then
		CFLAGS="${CFLAGS} -fPIC"
	fi

	# Static linking against Tcl; on Windows this drops dllimport
	CPPFLAGS="${CPPFLAGS} -DSTATIC_BUILD ${TCL_INCLUDE_SPEC} -Isrc -Isrc/optional"

	# tclConfig.sh describes the target; Windows uses BCryptGenRandom
	if [ "${TCL_SHLIB_SUFFIX}" != '.dll' ] && have_getentropy; then
		CPPFLAGS="${CPPFLAGS} -DMONOCYPHER_HAVE_GETENTROPY"
	fi

	return 0
}

function build() {
	local source

	for source in src/monocypher.c src/optional/monocypher-ed25519.c tclmonocypher.c; do
		${CC:-cc} ${CPPFLAGS} ${CFLAGS} -c "${source}" -o "$(basename "${source}" .c).o" || return 1
	done

	rm -f "libmonocypher${tclpkgversion}.a"
	${AR:-ar} cr "libmonocypher${tclpkgversion}.a" monocypher.o monocypher-ed25519.o tclmonocypher.o || return 1
	${RANLIB:-ranlib} "libmonocypher${tclpkgversion}.a" || return 1
}

function install() {
	local libdir

	libdir="${installdir}/lib/monocypher${tclpkgversion}"
	mkdir -p "${libdir}" "${installdir}/include" || return 1

	cp "libmonocypher${tclpkgversion}.a" LICENCE.md "${libdir}/" || return 1
	cp src/monocypher.h src/optional/monocypher-ed25519.h "${installdir}/include/" || return 1

	# BCryptGenRandom
	if [ "${TCL_SHLIB_SUFFIX}" = '.dll' ]; then
		echo '-lbcrypt' > "${libdir}/libmonocypher${tclpkgversion}.a.linkadd"
	fi
}
