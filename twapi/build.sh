#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='5.2.0'
url="https://github.com/apnadkarni/twapi/archive/refs/tags/v${version}.tar.gz"
sha256='946e5bb7433aad14def33b56ce66a9d9423f00de775fa19fc9f71e134cfa7198'

function postinstall() {

    find "${installdir}" -type f -name '*.a' | while IFS='' read -r filename; do

        # Makefile dyncall lib path is relative to the workdir
        twapi_libs="$(grep '^LIBS[[:space:]]*=' "${workdir}/Makefile" |
                              sed -e 's@^LIBS[[:space:]]*=[[:space:]]*@@' \
                                  -e "s@\\./dyncall@${workdir}/dyncall@g" |
                                      tr -d '\t')"

        echo "$twapi_libs" > "${filename}".linkadd
    done
}
