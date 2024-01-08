#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.4.16'
url="https://download.sourceforge.net/project/tkimg/tkimg/1.4/tkimg%20${version}/Img-${version}-Source.tar.gz"
sha256='d99af4835fe3e20960817c7a1b5235dcfaa97c642593cce50bdb64c5827cd321'

# zlibtcl has different version than enclosing Img package
tclpkgversion='1.2.13'

function preconfigure() {
	# Only interested in compiling zlibtcl sub-project
	cd zlib
}
