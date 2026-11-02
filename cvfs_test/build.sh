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

"${TCLSH_NATIVE}" "${buildsrcdir}/mktree.tcl" "${runtimepkgdir}" || exit 1
cp "${buildsrcdir}/cvfs_test.tcl" "${buildsrcdir}/pkgIndex.tcl" "${runtimepkgdir}/" || exit 1
cp -r "${buildsrcdir}/tests" "${runtimepkgdir}/" || exit 1

# cvfs_test::run reads the test file names from here: in the kit, tests/ is on
# the CVFS under test, and a broken glob there could skip test files unnoticed
(cd "${runtimepkgdir}/tests" && ls) > "${runtimepkgdir}/tests.txt" || exit 1
