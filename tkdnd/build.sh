#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="2.9.5"
url="https://github.com/petasis/tkdnd/archive/refs/tags/tkdnd-release-test-v${version}.tar.gz"
sha256='7ab2d1d7c0f57a5dc7f6d5542895b44762a31a01621c9d7f80f3bbd67c7bcc39'

configure_extra=(--with-tk=${KITCREATOR_DIR}/tk/inst/lib)

function postinstall() {
	if [ "${pkg_configure_shared_build}" = '0' ]; then
		(
			eval "$(grep '^PKG_LIBS=' config.log)" || exit 1

			find "${installdir}" -type f -name '*.a' | while IFS='' read -r filename; do
				echo "${PKG_LIBS}" > "${filename}.linkadd"
			done
		) || return 1
	fi
}
