#! /usr/bin/env bash

if [ ! -f 'build.sh' ]; then
	echo 'ERROR: This script must be run from the directory it is in' >&2

	exit 1
fi
if [ -z "${TCLVERS}" ]; then
	echo 'ERROR: The TCLVERS environment variable is not set' >&2

	exit 1
fi

MK4VERS="2.4.9.8"
SRC="src/metakit-${MK4VERS}.tar.gz"
SRCURL="https://github.com/TclMonster/metakit/archive/refs/tags/${MK4VERS}.tar.gz"
SRCHASH='9e7579d3f4750e7e014a4ea6bf8d715bbd043f39'
BUILDDIR="$(pwd)/build/metakit-${MK4VERS}"
OUTDIR="$(pwd)/out"
INSTDIR="$(pwd)/inst"
PATCHDIR="$(pwd)/patches"
export MK4VERS SRC SRCURL BUILDDIR OUTDIR INSTDIR PATCHDIR

# Set configure options for this sub-project
LDFLAGS="${LDFLAGS} ${KC_MK4TCL_LDFLAGS}"
CFLAGS="${CFLAGS} ${KC_MK4TCL_CFLAGS}"
CXXFLAGS="${CXXFLAGS} ${KC_MK4TCL_CXXFLAGS}"
CPPFLAGS="${CPPFLAGS} ${KC_MK4TCL_CPPFLAGS}"
LIBS="${LIBS} ${KC_MK4TCL_LIBS}"
export LDFLAGS CFLAGS CPPFLAGS LIBS

rm -rf 'build' 'out' 'inst'
mkdir 'build' 'out' 'inst' || exit 1

TCL_VERSION="unknown"
if [ -f "${TCLCONFIGDIR}/tclConfig.sh" ]; then
        source "${TCLCONFIGDIR}/tclConfig.sh"
fi
export TCL_VERSION

if [ ! -f "${SRC}" ]; then
	mkdir 'src' >/dev/null 2>/dev/null

	if [ ! -d 'buildsrc' ]; then
		download "${SRCURL}" "${SRC}" "${SRCHASH}" || exit 1
	fi
fi

(
	cd 'build' || exit 1

	if [ ! -d '../buildsrc' ]; then
		gzip -dc "../${SRC}" | tar -xf -
	else
		cp -rp ../buildsrc/* './'
	fi

	# Apply required patches
	cd "${BUILDDIR}" || exit 1
	for patch in "${PATCHDIR}/all"/metakit-${MK4VERS}-*.diff "${PATCHDIR}/${TCL_VERSION}"/metakit-${MK4VERS}-*.diff; do
		if [ ! -f "${patch}" ]; then
			continue
		fi

		echo "Applying: ${patch}"
		${PATCH:-patch} -p1 < "${patch}"
	done

	cd "${BUILDDIR}/unix" || exit 1

	BUILDTYPE="$(basename "${TCLCONFIGDIR}")"
	if [ "${BUILDTYPE}" = "win" ]; then
		if [ "${STATICMK4}" != "-1" ]; then
			if [ "${STATICMK4}" = "0" ]; then
				echo 'Warning: Metakit4 fails to build shared on Win32, converting to static linking'

				STATICMK4="1"
			fi
		else
			STATICMK4="0"
		fi
		export STATICMK4
	fi

	# Try to build as a shared object if requested
	if [ "${STATICMK4}" = "0" ]; then
		tryopts="--enable-shared --disable-shared"
	elif [ "${STATICMK4}" = "-1" ]; then
		tryopts="--enable-shared"
	else
		tryopts="--disable-shared"
	fi

	SAVE_CXXFLAGS="${CXXFLAGS}"
	for tryopt in $tryopts __fail__; do
		# Clean up, if needed
		make distclean >/dev/null 2>/dev/null
		rm -rf "${INSTDIR}"
		mkdir "${INSTDIR}"

		if [ "${tryopt}" = "__fail__" ]; then
			exit 1
		fi

		if [ "${tryopt}" == "--enable-shared" ]; then
			isshared="1"
		else
			isshared="0"
		fi

		if [ "${isshared}" = "0" -a "${BUILDTYPE}" = "win" ]; then
			CPPFLAGS="${CPPFLAGS} -DSTATIC_BUILD=1"  ;# Ensure DLL import/export attributes cleared
			export CPPFLAGS
		fi

		# If build a static Mk4tcl for KitDLL, ensure that we use PIC
		# so that it can be linked into the shared object
		if [ "${isshared}" = "0" -a "${KITTARGET}" = "kitdll" ]; then
			CXXFLAGS="${SAVE_CXXFLAGS} -fPIC"
		else
			CXXFLAGS="${SAVE_CXXFLAGS}"
		fi
		export CXXFLAGS

		(
			echo "Running: ./configure $tryopt --prefix=\"${INSTDIR}\" --exec-prefix=\"${INSTDIR}\" --libdir=\"${INSTDIR}/lib\" --with-tcl=\"${TCLCONFIGDIR}/../generic\" ${CONFIGUREEXTRA}"
			./configure $tryopt --prefix="${INSTDIR}" --exec-prefix="${INSTDIR}" --libdir="${INSTDIR}/lib" --with-tcl="${TCLCONFIGDIR}/../generic" ${CONFIGUREEXTRA}

			echo "Running: ${MAKE:-make} tcllibdir=\"${INSTDIR}/lib\" AR=\"${AR:-ar}\" RANLIB=\"${RANLIB:-ranlib}\""
			${MAKE:-make} tcllibdir="${INSTDIR}/lib" AR="${AR:-ar}" RANLIB="${RANLIB:-ranlib}" || exit 1

			echo "Running: ${MAKE:-make} tcllibdir=\"${INSTDIR}/lib\" AR=\"${AR:-ar}\" RANLIB=\"${RANLIB:-ranlib}\" install"
			${MAKE:-make} tcllibdir="${INSTDIR}/lib" AR="${AR:-ar}" RANLIB="${RANLIB:-ranlib}" install || exit 1
		) || continue

		break
	done

	# Clean up "libmk4.*", it's not needed
	rm -f "${INSTDIR}/lib"/libmk4.*

	# If we are building a shared version of Mk4tcl, put it in the VFS directory
	if [ "${isshared}" = "1" ]; then
		cp -r "${INSTDIR}/lib" "${OUTDIR}"
	fi

	exit 0
) || exit 1

exit 0
