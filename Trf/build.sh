#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='2.1.4'
url="https://downloads.sourceforge.net/project/tcltrf/tcltrf/${version}/trf${version}.tar.bz2"
sha256='179ce88b272bdfa44e551b858f6ee5783a8c72cc11a5ef29975b29d12998b3de'

STATICTRF=1

configure_extra=(
	# Force Trf to use internal md2, md5, and sha algorithms.
	# This drastically simplifies the build since md2 is not enabled by
	# default in OpenSSL—and completely missing from LibreSSL.
	trf_cv_path_SSL_INCLUDE_DIR=""
	trf_cv_lib_SSL_LIB_DIR=""

	# Also force internal bzip2 for convenience.
	trf_cv_path_BZ2_INCLUDE_DIR=""

	--with-zlib=${KITCREATOR_DIR}/zlib/inst

	--enable-static-bzlib
	--enable-static-zlib
	--enable-static-md5

	--with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include
	)
