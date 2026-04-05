#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0a0'
url="https://github.com/tclmonster/tclcompiler2/archive/refs/tags/v${version}.tar.gz"
sha256='f6669224a677d6bdc43e0c3ce1854d8cfd61ece561250d1e5d94e97085ccd627'

KC_TCLCOMPILER_CFLAGS='-Wno-error=implicit-function-declaration'
configure_extra=(--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include)
