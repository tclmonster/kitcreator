#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0'
url="http://sourceforge.net/projects/tcllib/files/tcllib/${version}/tcllib-${version}.tar.bz2"
sha256='196c574da9218cf8dcf180f38a603e670775ddb29f191960d6f6f13f52e56b04'

function build() {
    :
}

function install() {
    ${MAKE:-make} tcllibdir="${installdir}/lib" TCL_PACKAGE_PATH="${installdir}/lib" \
		  install-tcl || return 1
}
