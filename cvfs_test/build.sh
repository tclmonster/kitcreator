#! /usr/bin/env bash

# Test package for CVFS kits; see buildsrc/cvfs_test.tcl.  kitsh copies every
# built package's out/ into the kit, so with "./kitcreator retry" delete
# cvfs_test/out before building a kit that should not carry it.

pkgdir="$(pwd)"
buildsrcdir="${pkgdir}/buildsrc"
runtimedir="${pkgdir}/out"
runtimepkgdir="${runtimedir}/lib/cvfs_test"

rm -rf "${runtimedir}"
mkdir -p "${runtimedir}/lib" || exit 1

# mktree.tcl is UTF-8; Tcl 8.6 would otherwise read it in the system encoding
"${TCLSH_NATIVE}" -encoding utf-8 "${buildsrcdir}/mktree.tcl" "${runtimepkgdir}" || exit 1
cp "${buildsrcdir}/cvfs_test.tcl" "${buildsrcdir}/pkgIndex.tcl" "${runtimepkgdir}/" || exit 1
cp -r "${buildsrcdir}/tests" "${runtimepkgdir}/" || exit 1
