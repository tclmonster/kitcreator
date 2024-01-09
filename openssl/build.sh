#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='3.2.0'
url="https://www.openssl.org/source/openssl-${version}.tar.gz"
sha256='14c826f07c7e433706fb5c69fa9e25dab95684844b4c962a2cf1bf183eb4690e'

# NOTE: Right now this does not work for cross-compiling
# --cross-compile-prefix=<PREFIX>
# --openssldir:
#	Windows:
#		C:\Program Files\Common Files\SSL
# or	C:\Program Files (x86)\Common Files\SSL
#
#	Unix:
#		/usr/local/ssl
#		
function configure() {
	./Configure no-shared enable-md2 \
	--prefix="${installdir}" --libdir="${installdir}/lib" \
	--with-zlib-lib=${KITCREATOR_DIR}/zlib/inst/lib \
	--with-zlib-include=${KITCREATOR_DIR}/zlib/inst/include \
		|| return 1
}

function build() {
	${MAKE:-make} build_libs || return 1
}

function postinstall() {
	printf 'libcrypto.a\nlibssl.a\n' > "${installdir}/kitcreator-nolibs"
}

#function install() {
#	${MAKE:-make} install || return 1
#}

#function createruntime() {
#	:
#}
