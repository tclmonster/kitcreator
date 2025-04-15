#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="3.12.9"
url="https://github.com/tclmonster/cpython-mingw.git"
# sha256='ad83cda00a8a30adbad263d8e25455397be0641ded65d731b78ec178ed74570c'
pkg_always_static=1

# For MSYS2
KC_CPYTHON_LDFLAGS='-static -lversion -lws2_32 -lpathcch -lbcrypt -ladvapi32 -lkernel32 -luser32'

configure_extra=(--with-static-libpython
		 --with-build-python="${workdir}"/bootstrap-py/bin/python3.12.exe
		 --with-system-expat
		 --with-system-libmpdec
		 --without-ensurepip
		 --disable-test-modules)

download() {
	if [ -d "${buildsrcdir}" ]; then
		return 0
	fi
	mkdir -p "${buildsrcdir}"
	git clone --depth 1 --branch mingw-v${version} ${url} "${buildsrcdir}"
}

preconfigure() {
	#cp -f "${pkgdir}"/Setup.local "${workdir}"/Modules

	autoreconf -vfi

	# Build the bootstrap python first in order to freeze standard modules.
	mkdir -p "${workdir}"/bootstrap-py

	./configure --prefix="${workdir}"/bootstrap-py \
		    --enable-shared \
		    --with-system-expat \
		    --with-system-libmpdec \
		    --without-ensurepip \
		    --disable-test-modules
	make
	make install
	make clean

	export MODULE_BUILDTYPE=static ;# Ensure standard modules will be static.
}

postconfigure() {
	sed -i 's/getpath_noop.o/getpath.o/g' Makefile ;# Force build to link getpath.o
}

# TODO: patch configure.ac to set FREEZE_MODULE_BOOTSTRAP & *_DEPS
# in order to force use the --with-build-python supplied python instead
# of compiling _bootstrap_python. Or, try to trick it into a cross-compiling
# situation with --host and --build.
