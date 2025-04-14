#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="3.14.0a7"
url="https://github.com/python/cpython/archive/refs/tags/v${version}.tar.gz"
sha256='ad83cda00a8a30adbad263d8e25455397be0641ded65d731b78ec178ed74570c'
pkg_always_static=1

# configure_extra=(--with-tk=${KITCREATOR_DIR}/tk/inst/lib)

preconfigure() {
	cp -f "${pkgdir}"/Setup.local "${workdir}"/Modules
}
