#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="2.9.5"
url="https://github.com/petasis/tkdnd/archive/refs/tags/tkdnd-release-test-v${version}.tar.gz"
sha256='7ab2d1d7c0f57a5dc7f6d5542895b44762a31a01621c9d7f80f3bbd67c7bcc39'

configure_extra=(--with-tk=${KITCREATOR_DIR}/tk/inst/lib)
