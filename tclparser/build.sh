#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.4'
url="https://github.com/bandoti/tclparser/archive/refs/tags/v${version}.tar.gz"
sha256='cce5b4131fb81b2027500b15ad0f4daf3d26053aec4febf296483b040412b7b7'

configure_extra="--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include"
