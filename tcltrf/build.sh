#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.1.4'
url="https://downloads.sourceforge.net/project/tcltrf/tcltrf/${version}/trf${version}.tar.bz2"
sha256='179ce88b272bdfa44e551b858f6ee5783a8c72cc11a5ef29975b29d12998b3de'

STATICTCLTRF=-1

configure_extra=(
	--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include
	--with-zlib=${KITCREATOR_DIR}/zlib/inst
	--with-bz2=/ucrt64
	--with-ssl=${KITCREATOR_DIR}/openssl/inst
	--enable-static-zlib
	--enable-static-bzlib
	--enable-static-md5
	)
