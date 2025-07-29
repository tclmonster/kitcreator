#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='5.1.0'
url="https://github.com/apnadkarni/twapi/archive/refs/tags/v${version}.tar.gz"
sha256='1ad8bf29c419e684bb653e5b11556f0cf74ab6d78bd59d5345d5bf550d6e3363'

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
