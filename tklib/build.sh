#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='0.7'
url="https://core.tcl-lang.org/tklib/tarball/tklib-${version}.tar.gz?uuid=tklib-${version}"
sha256='b28d0e92bf56d0c2b106b7a2b9ad1f82f59db3864e25e5a3541b52d9c3f56a97'

configure_extra=(--with-tk=${KITCREATOR_DIR}/tk/inst/lib)
