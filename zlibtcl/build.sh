#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.0.1'
url="https://download.sourceforge.net/project/tkimg/tkimg/2.0/tkimg%20${version}/Img-${version}-Source.tar.gz"
sha256='e69d31b3f439a19071e3508a798b9d5dc70b9416e00926cdac12c1c2d50fce83'

# zlibtcl has different version than enclosing Img package
tclpkgversion='1.3.1'

function preconfigure() {
	# Only interested in compiling zlibtcl sub-project
	cd zlib
}
