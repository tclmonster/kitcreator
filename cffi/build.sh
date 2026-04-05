#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0.3'
url="https://sourceforge.net/projects/magicsplat/files/cffi/cffi${version}-src.tar.gz"
sha256='8f9b7e7aa2beb105a7d86ad880a5e279d11c380cc83b1ae0ad038bf128573edc'

function postinstall() {

    find "${installdir}" -type f -name '*.a' | while IFS='' read -r filename; do

        cffi_libs="$(grep '^LIBS[[:space:]]*=' "${workdir}/Makefile" |
                              sed -e 's@^LIBS[[:space:]]*=[[:space:]]*@@' \
                                  -e 's@$(TCL_TOMMATH_LIB)@@g' |
                                      tr -d '\t')"

        echo "$cffi_libs" > "${filename}".linkadd
    done
}
