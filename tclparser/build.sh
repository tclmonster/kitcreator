#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.4'
url="https://github.com/bandoti/tclparser/archive/refs/tags/v${version}.tar.gz"
sha256='d30cc1f93945f8f962214b7b76ff9ea9016285227b2fbd0293c7a90489e0eedd'

configure_extra=(--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include)
