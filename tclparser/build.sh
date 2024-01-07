#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.4'
url="https://github.com/bandoti/tclparser/archive/refs/tags/v${version}.tar.gz"
sha256='b45ebe44787c9efe40a3b47554b1e3a4e6b78bacf19c1b63abe5be9721705926'

configure_extra="--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include"
