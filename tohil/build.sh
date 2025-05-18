#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="4.4.2"
url="https://github.com/tclmonster/tohil.git"
# sha256='ad83cda00a8a30adbad263d8e25455397be0641ded65d731b78ec178ed74570c'

configure_extra=(--with-python-include="${KITCREATOR_DIR}"/cpython/inst/include/python3.12
		 --with-python-lib="${KITCREATOR_DIR}"/cpython/inst/lib
		 --with-python-version='3.12')
# For MSYS2
KC_TOHIL_LDFLAGS='-lversion -lws2_32 -lpathcch -lbcrypt -ladvapi32 -lkernel32 -luser32'

download() {
	if [ -f "${buildsrcdir}"/configure.ac ]; then
		return 0
	fi
	mkdir -p "${buildsrcdir}"
	git clone --depth 1 --branch static-build ${url} "${buildsrcdir}"
}

preconfigure() {
	autoreconf -vfi
}
