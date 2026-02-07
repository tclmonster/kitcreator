#! /usr/bin/env bash

pkgdir="$(pwd)"
buildsrcdir="${pkgdir}/buildsrc"
installdir="${pkgdir}/inst/go-pkg"

rm -rf "${installdir}"
mkdir -p "${installdir}" || exit 1
cp "${buildsrcdir}"/*.go "${buildsrcdir}"/go.mod "${installdir}/" || exit 1
