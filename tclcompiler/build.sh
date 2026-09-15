#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0a0'
url="https://github.com/tclmonster/tclcompiler2/archive/refs/tags/v${version}.tar.gz"
sha256='194c55fb1c7e40bae6b038de174ecd6ec4d6694a7dd9a57c1ef14b93a7a936a1'

KC_TCLCOMPILER_CFLAGS='-Wno-error=implicit-function-declaration'
configure_extra=(--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include)
