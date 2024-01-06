#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.7'
url="https://github.com/bandoti/tbcload/archive/refs/tags/v${version}.tar.gz"
sha256='12de0a9b6e777a42f4037c8b4a59e7613f8034cd43b8a4475dedfce82d728fd6'

function postinstall() {
	cp -r "${installdir}/include" "${runtimedir}" || return 1
}
