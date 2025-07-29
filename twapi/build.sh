#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='5.1.0'
url="https://github.com/apnadkarni/twapi/archive/refs/tags/v${version}.tar.gz"
sha256='1ad8bf29c419e684bb653e5b11556f0cf74ab6d78bd59d5345d5bf550d6e3363'

function postinstall() {
    # TODO: add the dyncall dependency for static builds. At the
    # moment it is currently missing, so the static build won't work.

    find "${installdir}" -type f -name '*.a' | while IFS='' read -r filename; do
        echo '-lole32 -loleaut32 -lwtsapi32 -lcrypt32 -lwintrust -luuid -lsetupapi -lcfgmgr32 -ltdh -lwinmm -liphlpapi -lpsapi -lpowrprof -lpdh -lshlwapi -lversion -lgdi32 -lsecur32 -lcredui -lmpr -luxtheme -lrpcrt4 -lwinspool' > "${filename}".linkadd
    done
}
