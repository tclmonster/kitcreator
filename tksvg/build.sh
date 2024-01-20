#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='0.14'
url="https://github.com/oehhar/tksvg/archive/refs/tags/${version}.tar.gz"
sha256='f965c52050148e9ab926c90d9e8cf3609b187c55f850c5c31f2997dab1c8361a'

configure_extra=(--with-tk=${KITCREATOR_DIR}/tk/inst/lib)
