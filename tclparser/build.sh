#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.4'
url="https://github.com/bandoti/tclparser/archive/refs/tags/v${version}.tar.gz"
sha256='29c2fdb1db7e9b29dc357364a74ff78f14dcf627ed662643b15f8fbe1e991a9b'

configure_extra=(--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include)
