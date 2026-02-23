#! /usr/bin/env bash

pkgdir="$(pwd)"
buildsrcdir="${pkgdir}/buildsrc"
installdir="${pkgdir}/inst/go-pkg"
runtimedir="${pkgdir}/out"

rm -rf "${installdir}" "${runtimedir}"
mkdir -p "${installdir}" || exit 1
cp "${buildsrcdir}"/*.go "${buildsrcdir}"/*.h "${buildsrcdir}"/go.mod "${installdir}/" || exit 1

runtimepkgdir="${runtimedir}/lib/crypto"
mkdir -p "${runtimepkgdir}" || exit 1
cp "${buildsrcdir}/pkgIndex.tcl" "${runtimepkgdir}/" || exit 1
