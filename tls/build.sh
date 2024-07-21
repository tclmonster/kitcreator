#! /usr/bin/env bash

# BuildCompatible: KitCreator

version="1.8.0"
commit_hash="1505883e4a"
url="https://core.tcl-lang.org/tcltls/tarball/${commit_hash}/tcltls-${commit_hash}.tar.gz"
sha256='a57d7b6b3710e6966387f0b2269e6a014b7b8b2db736e44d982af5318adeefba'
configure_extra=(--enable-deterministic --with-tclinclude=${KITCREATOR_DIR}/tcl/inst/include)

function buildSSLLibrary() {
	local version url hash
	local archive

	version='3.9.2'
	url="http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${version}.tar.gz"
	hash='7b031dac64a59eb6ee3304f7ffb75dad33ab8c9d279c847f92c89fb846068f97'

	archive="src/libressl-${version}.tar.gz"

	echo " *** Building LibreSSL v${version}" >&2

	if [ ! -e "${pkgdir}/${archive}" ]; then
		"${_download}" "${url}" "${pkgdir}/${archive}" "${hash}" || return 1
	fi

	(
		rm -rf libressl-*

		gzip -dc "${pkgdir}/${archive}" | tar -xf - || exit 1

		cd "libressl-${version}" || exit 1

		# This defeats hardening attempts that break on various platforms
		CFLAGS=' -g -O0 '
		export CFLAGS

		./configure ${CONFIGUREEXTRA} --with-pic --disable-shared --enable-static --prefix="$(pwd)/INST" || exit 1

		# Disable building the apps -- they do not get used
		rm -rf apps
		mkdir apps
		cat << \_EOF_ > apps/Makefile
%:
	@echo Nothing to do
_EOF_

		${MAKE:-make} V=1 || exit 1

		${MAKE:-make} V=1 install || exit 1
	) || return 1

	# We always statically link
	KC_TLS_LINKSSLSTATIC='1'

	SSLPKGCONFIGDIR="$(pwd)/libressl-${version}/INST/lib/pkgconfig"

	return 0
}

function preconfigure() {
	# Determine SSL directory
	if [ -z "${CPP}" ]; then
		CPP="${CC:-cc} -E"
	fi

	SSLPKGCONFIGDIR=''
	SSLDIR=''

	if [ -n "${KC_TLS_SSLDIR}" ]; then
		case "${KC_TLS_SSLDIR}" in
			*/pkgconfig|*/pkgconfig/)
				SSLPKGCONFIGDIR="${KC_TLS_SSLDIR}"
				;;
			*)
				SSLDIR="${KC_TLS_SSLDIR}"
				;;
		esac
	else
		SSLGUESS='0'
		if [ -z "${KC_TLS_BUILDSSL}" ]; then
			if ! "${PKG_CONFIG:-pkg-config}" --exists openssl >/dev/null 2>/dev/null; then
				SSLDIR="$(echo '#include <openssl/ssl.h>' 2>/dev/null | ${CPP} - 2> /dev/null | awk '/# 1 "\/.*\/ssl\.h/{ print $3; exit }' | sed 's@^"@@;s@"$@@;s@/include/openssl/ssl\.h$@@')"
			else
				SSLGUESS='1'
			fi
		fi

		if [ -z "${SSLDIR}" -a "${SSLGUESS}" = '0' ]; then
			buildSSLLibrary || SSLPKGCONFIGDIR=''
		fi

		if [ -z "${SSLPKGCONFIGDIR}" -a -z "${SSLDIR}" -a "${SSLGUESS}" = '0' ]; then
			echo "Unable to find OpenSSL, aborting." >&2

			return 1
		fi
	fi

	# Add SSL library to configure options
	if [ -n "${SSLPKGCONFIGDIR}" ]; then
		configure_extra=("${configure_extra[@]}" --with-openssl-pkgconfig="${SSLPKGCONFIGDIR}")
	elif [ -n "${SSLDIR}" ]; then
		configure_extra=("${configure_extra[@]}" --with-openssl-dir="${SSLDIR}")
	fi

	# If we are statically linking to libssl, let tcltls know so it asks for the right
	# packages
	if [ "${KC_TLS_LINKSSLSTATIC}" = '1' ]; then
		configure_extra=("${configure_extra[@]}" --enable-static-ssl)
	fi
}

function expandLinkLibs {
	echo "$PKG_LIBS" | awk '
BEGIN {
  path="";
  libs="";

} {
  for (i=1; i <= NF; i++) {
    if ($i ~ /^-L/)
      path=substr($i,3)
    if ($i ~ /^-l/)
      libs=libs " " path "/lib" substr($i,3) ".a"
  }
}
END {
  print libs
}'
}

function getcc {
	grep -i 'ac_cv_prog_ac_ct_CC' config.log | awk -F= '{print $2}'
}

function shouldExpandLinkLibs {
	case "$KC_CROSSCOMPILE_HOST_OS" in
	    *darwin*)
		$(getcc) --version | grep -qi clang
		;;
	    *)
		false
		;;
	esac
}

function postinstall() {
	if [ "${pkg_configure_shared_build}" = '0' ]; then
		(
			eval "$(grep '^PKG_LIBS=' config.log)" || exit 1

			find "${installdir}" -type f -name '*.a' | while IFS='' read -r filename; do
				if shouldExpandLinkLibs; then
					expandLinkLibs > "${filename}.linkadd"
				else
					echo "${PKG_LIBS}" > "${filename}.linkadd"
				fi
			done
		) || return 1
	fi
}
