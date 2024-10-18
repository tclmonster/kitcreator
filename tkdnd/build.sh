#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="2.9.4"
url="https://github.com/petasis/tkdnd/archive/refs/tags/tkdnd-release-test-v${version}.tar.gz"
sha256='cc6d3f0b7daca9564869e29e5db0996caa5f0c03d21c9b7032bad43f0a58121c'

configure_extra=(--with-tk=${KITCREATOR_DIR}/tk/inst/lib)
