#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="1.3.1"
url="https://github.com/madler/zlib/releases/download/v${version}/zlib-${version}.tar.gz"
sha256='9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23'

function configure() {
	case "$(uname -s 2>/dev/null | dd conv=lcase 2>/dev/null)" in
		mingw*)
			cp win32/Makefile.gcc Makefile

			make_extra=(BINARY_PATH="${installdir}/bin" INCLUDE_PATH="${installdir}/include" LIBRARY_PATH="${installdir}/lib")

			make_extra+=(--jobs=1) ;# Prevent a race-condition during STRIP

			for var in CC AR STRIP; do
			    local val=$(eval "echo \${$var}")
			    if [ -n "$val" ]; then
				    make_extra+=($var="$val")
			    fi
			done
			;;
		*)
			if [ "${KITTARGET}" = "kitdll" ]; then
				CFLAGS="${CFLAGS} -fPIC"
				export CFLAGS
			fi

			./configure --prefix="${installdir}" --libdir="${installdir}/lib" --static
			;;
	esac
}

function createruntime() {
	:
}
