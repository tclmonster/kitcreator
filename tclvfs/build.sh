#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="1.5.0"
url="https://core.tcl-lang.org/tclvfs/tarball/tclvfs-20251211172729-77037fcb2c.tar.gz"
sha256='4788f023cc3f850820f4c8a662783ea7d6dceccecf7df247dabf4435e9201fbc'

function init_kitcreator() {
	pkg_always_static='1'
}
