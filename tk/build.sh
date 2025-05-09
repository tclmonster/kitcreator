#! /usr/bin/env bash

if [ ! -f 'build.sh' ]; then
	echo 'ERROR: This script must be run from the directory it is in' >&2

	exit 1
fi
if [ -z "${TCLVERS}" ]; then
	echo 'ERROR: The TCLVERS environment variable is not set' >&2

	exit 1
fi

case "${TCLVERS}" in
	*:*)
		TCLVERS_CLEAN="$(echo "${TCLVERS}" | sed 's@:@_@g')"
		;;
	*)
		TCLVERS_CLEAN="${TCLVERS}"
		;;
esac

SRC="src/tk${TCLVERS}.tar.gz"
SRCURL="http://prdownloads.sourceforge.net/tcl/tk${TCLVERS}-src.tar.gz"
SRCHASH='-'
BUILDDIR="$(pwd)/build/tk${TCLVERS_CLEAN}"
PATCHDIR="$(pwd)/patches"
OUTDIR="$(pwd)/out"
INSTDIR="$(pwd)/inst"
PATCHSCRIPTDIR="$(pwd)/patchscripts"
export SRC SRCURL BUILDDIR PATCHDIR OUTDIR INSTDIR PATCHSCRIPTDIR

case "${TCLVERS}" in
	8.6.4)
		SRCHASH='08f99df85e5dc9c4271762163c6aabb962c8b297dc5c4c1af8bdd05fc2dd26c1'
		;;
	8.6.5)
		SRCHASH='fbbd93541b4cd467841208643b4014c4543a54c3597586727f0ab128220d7946'
		;;
	8.6.6)
		SRCHASH='d62c371a71b4744ed830e3c21d27968c31dba74dd2c45f36b9b071e6d88eb19d'
		;;
	8.6.7)
		SRCHASH='061de2a354f9b7c7d04de3984c90c9bc6dd3a1b8377bb45509f1ad8a8d6337aa'
		;;
	8.6.8)
		SRCHASH='49e7bca08dde95195a27f594f7c850b088be357a7c7096e44e1158c7a5fd7b33'
		;;
	8.6.9)
		SRCHASH='d3f9161e8ba0f107fe8d4df1f6d3a14c30cc3512dfc12a795daa367a27660dac'
		;;
	8.6.10)
		SRCHASH='63df418a859d0a463347f95ded5cd88a3dd3aaa1ceecaeee362194bc30f3e386'
		;;
	8.6.11)
		SRCHASH='5228a8187a7f70fa0791ef0f975270f068ba9557f57456f51eb02d9d4ea31282'
		;;
	8.6.12)
		SRCHASH='12395c1f3fcb6bed2938689f797ea3cdf41ed5cb6c4766eec8ac949560310630'
		;;
	8.6.13)
		SRCHASH='2e65fa069a23365440a3c56c556b8673b5e32a283800d8d9b257e3f584ce0675'
		;;
	8.6.14)
		SRCHASH='8ffdb720f47a6ca6107eac2dd877e30b0ef7fac14f3a84ebbd0b3612cee41a94'
		;;
	8.6.15)
		SRCHASH='550969f35379f952b3020f3ab7b9dd5bfd11c1ef7c9b7c6a75f5c49aca793fec'
		;;
	8.6.16)
		SRCHASH='be9f94d3575d4b3099d84bc3c10de8994df2d7aa405208173c709cc404a7e5fe'
		;;
esac

# Set configure options for this sub-project
LDFLAGS="${LDFLAGS} ${KC_TK_LDFLAGS}"
CFLAGS="${CFLAGS} ${KC_TK_CFLAGS}"
CPPFLAGS="${CPPFLAGS} ${KC_TK_CPPFLAGS}"
LIBS="${LIBS} ${KC_TK_LIBS}"
export LDFLAGS CFLAGS CPPFLAGS LIBS

# Must be kept in-sync with "../tcl/build.sh"
TCLFOSSILDATE="../tcl/src/tcl${TCLVERS}.tar.gz.date"
export TCLFOSSILDATE

rm -rf 'build' 'out' 'inst'
mkdir 'build' 'out' 'inst' || exit 1

# Determine Tcl version
TCL_VERSION="unknown"
if [ -f "${TCLCONFIGDIR}/tclConfig.sh" ]; then
	source "${TCLCONFIGDIR}/tclConfig.sh"
fi
export TCL_VERSION


if [ ! -f "${SRC}" ]; then
	mkdir 'src' >/dev/null 2>/dev/null

	use_fossil='0'
	if echo "${TCLVERS}" | grep '^cvs_' >/dev/null; then
		use_fossil='1'

		FOSSILTAG=$(echo "${TCLVERS}" | sed 's/^cvs_//g')
		if [ "${FOSSILTAG}" = "HEAD" ]; then
			FOSSILTAG="trunk"
		fi
	elif echo "${TCLVERS}" | grep '^fossil_' >/dev/null; then
		use_fossil='1'

		if echo "${TCLVERS}" | grep '^fossil_.*_tk=' >/dev/null; then
			FOSSILTAG=$(echo "${TCLVERS}" | sed 's/^fossil_.*_tk=//g')
		else
			FOSSILTAG=$(echo "${TCLVERS}" | sed 's/^fossil_//g')
		fi
	fi

	if [ -d 'buildsrc' ]; then
		# Override here to avoid downloading tarball from Fossil if we
		# have a particular tree already available.
		use_fossil='0'
	fi

	if [ "${use_fossil}" = "1" ]; then
		(       
			FOSSILDATE="$(cat "${TCLFOSSILDATE}" 2>/dev/null)"

			cd src || exit 1

			workdir="tmp-$$${RANDOM}${RANDOM}${RANDOM}"
			rm -rf "${workdir}"

			mkdir "${workdir}" || exit 1
			cd "${workdir}" || exit 1

			download "http://core.tcl.tk/tk/tarball/tk-fossil.tar.gz?uuid=${FOSSILTAG}" "tmp-tk.tar.gz" - || rm -f 'tmp-tk.tar.gz'
			gzip -dc "tmp-tk.tar.gz" | tar -xf - || rm -f 'tmp-tk.tar.gz'

			if [ ! -s 'tmp-tk.tar.gz' ]; then
				download "http://core.tcl.tk/tk/tarball/tk-fossil.tar.gz?uuid=${FOSSILDATE}" "tmp-tk.tar.gz" - || rm -f 'tmp-tk.tar.gz'
				gzip -dc "tmp-tk.tar.gz" | tar -xf -
			fi

			mv "tk-fossil" "tk${TCLVERS_CLEAN}"
                        
			tar -cf - "tk${TCLVERS_CLEAN}" | gzip -c > "../../${SRC}"

			cd ..
			rm -rf "${workdir}"
		)
	else
		if [ ! -d 'buildsrc' ]; then
			download "${SRCURL}" "${SRC}" "${SRCHASH}" || exit 1
		fi
	fi
fi

(
	cd 'build' || exit 1

	if [ ! -d '../buildsrc' ]; then
		gzip -dc "../${SRC}" | tar -xf -
	else    
		cp -rp ../buildsrc/* './'
	fi

	cd "${BUILDDIR}" || exit 1

	# Determine Tk version
	TK_VERSION="$(grep '^#.*define.*TK_VERSION' generic/tk.h 2>/dev/null | sed 's@^# *define[[:space:]][[:space:]]*TK_VERSION[[:space:]][[:space:]]*\"@@;s@\"$@@' 2>/dev/null | head -n 1)"
	if [ -z "${TK_VERSION}" ]; then
		TK_VERSION="unknown"
	fi
	export TK_VERSION

	echo "Note: TCL_VERSION=\"${TCL_VERSION}\""
	echo "Note: TK_VERSION=\"${TK_VERSION}\""

	(
		# Apply required patches
		cd "${BUILDDIR}" || exit 1
		for patch in "${PATCHDIR}/all"/tk-${TK_VERSION}-*.diff "${PATCHDIR}/${TCL_VERSION}"/tk-${TK_VERSION}-*.diff; do
			if [ ! -f "${patch}" ]; then
				continue
			fi

			echo "Applying: ${patch}"
			${PATCH:-patch} -p1 < "${patch}"
		done
	)

	# Apply patch scripts if needed
	for patchscript in "${PATCHSCRIPTDIR}"/*.sh; do
		if [ -f "${patchscript}" ]; then
			echo "Running patch script: ${patchscript}"
                                
			(
				. "${patchscript}"
			)
		fi
	done

	# Allow wrapper programs to supplant real programs
	if [ -d 'fake-bin' ]; then
		PATH="$(pwd)/fake-bin:${PATH}"
		export PATH
	fi

	for dir in "${TCLCONFIGDIRTAIL}" unix win macosx win64 __fail__; do
		if [ -z "${dir}" ]; then
			continue
		fi

		if [ "${dir}" = "__fail__" ]; then
			exit 1
		fi

		# Windows/amd64 workarounds
		win64="0"
		if [ "${dir}" = "win64" ]; then
			win64="1"
			dir="win"
		fi

		# Remove previous directory's "tkConfig.sh" if found
		rm -f 'tkConfig.sh'

		cd "${BUILDDIR}/${dir}" || exit 1

		# Remove broken pre-generated Makfiles
		rm -f GNUmakefile Makefile makefile

		if [ "${dir}" = "win" ]; then
			# Statically link Tk to Tclkit if we are compiling for
			# Windows unless otherwise requested
			if [ -z "${STATICTK}" ]; then
				STATICTK="1"
			fi

			if [ "${win64}" = "1" ]; then
				# Mingw32 for AMD64 requires this, apparently
				CPPFLAGS="${CPPFLAGS} -D_WIN32_IE=0x0501"
				CFLAGS="${CFLAGS} -D_WIN32_IE=0x0501"
				export CPPFLAGS CFLAGS
			fi
		fi

		if [ "${STATICTK}" = "1" ]; then
			echo "Running: ./configure --disable-shared --disable-symbols --prefix=\"${INSTDIR}\" --libdir=\"${INSTDIR}/lib\" --with-tcl=\"${TCLCONFIGDIR}\" ${CONFIGUREEXTRA}"
			./configure --disable-shared --disable-symbols --prefix="${INSTDIR}" --libdir="${INSTDIR}/lib" --with-tcl="${TCLCONFIGDIR}" ${CONFIGUREEXTRA} || continue
		else
			echo "Running: ./configure --enable-shared --disable-symbols --prefix=\"${INSTDIR}\" --libdir=\"${INSTDIR}/lib\" --with-tcl=\"${TCLCONFIGDIR}\" ${CONFIGUREEXTRA}"
			./configure --enable-shared --disable-symbols --prefix="${INSTDIR}" --libdir="${INSTDIR}/lib" --with-tcl="${TCLCONFIGDIR}" ${CONFIGUREEXTRA} || continue
		fi

		echo "Running: ${MAKE:-make}"
		${MAKE:-make} || (
			# Workaround a bug in Tk on FreeBSD 8.1:
			#   https://sourceforge.net/tracker/?func=detail&atid=112997&aid=3107390&group_id=12997
			LIBTKFILE="$(ls libtk*.so.1 2>/dev/null | head -1)"
			if [ -f "${LIBTKFILE}" ]; then
				NEWLIBTKFILE="$(echo "${LIBTKFILE}" | sed 's@\.so\.1@.so@')"
				cp "${LIBTKFILE}" "${NEWLIBTKFILE}"
			fi

			${MAKE:-make}
		) || continue

		private_headers=
		if echo " ${CONFIGUREEXTRA} " | grep ' --enable-tcl-private-headers ' \
				> /dev/null 2>&1; then

			private_headers=install-private-headers
		fi

		echo "Running: ${MAKE:-make} install $private_headers"
		${MAKE:-make} install $private_headers || continue

		# Update to include resources, if found
		if [ "${dir}" = "win" ]; then
			echo ' *** Importing user-specified icon'
			cp "${KITCREATOR_ICON}" rc/tk.ico

			echo ' *** Importing user-specified resources'
			cat "${KITCREATOR_RC}" | grep -v '^ *tclsh  *ICON' >> "./rc/tk_base.rc"

			if [ -f "$KITCREATOR_DIR/tclkit.exe.manifest" ]; then
				KITCREATOR_MANIFEST="$KITCREATOR_DIR/tclkit.exe.manifest"
			else
				KITCREATOR_MANIFEST="$BUILDDIR/win/wish.exe.manifest"
			fi
			echo " *** Creating tclkit.exe.manifest from $KITCREATOR_MANIFEST"
			cat "${KITCREATOR_MANIFEST}" | sed 's@name="Tcl.Tk.wish"@name="Tcl.tclkit"@' >> tclkit.exe.manifest

			echo ' *** Creating tkbase.res.o to support Windows build'
			echo "\"${RC:-windres}\" -o tkbase.res.o  --define STATIC_BUILD --include \"./../generic\" --include \"${TCLCONFIGDIR}/../generic\" --include \"${TCLCONFIGDIR}\" --include \"./rc\" \"./rc/tk_base.rc\""
			"${RC:-windres}" -o tkbase.res.o  --define STATIC_BUILD --include "./../generic" --include "${TCLCONFIGDIR}/../generic" --include "${TCLCONFIGDIR}" --include "./rc" "./rc/tk_base.rc"

			if [ -f "tkbase.res.o" ]; then
				cp "tkbase.res.o" "${INSTDIR}/lib/"
			fi
		fi

		if [ "${STATICTK}" = "1" ]; then
			# If we are building statically, don't create a
			# pkgIndex.tcl
			rm -f "${INSTDIR}"/lib/tk*/pkgIndex.tcl
		else
			# Update pkgIndex to load libtk from the local directory rather
			# than the parent directory
			for pkgIndex in "${INSTDIR}"/lib/tk*/pkgIndex.tcl; do
				sed 's@ \.\. bin @ @g;s@ \.\. @ @;s@ lib\(tk.*\.dll\)@ \1@' "${pkgIndex}" > "${pkgIndex}.new"
				mv "${pkgIndex}.new" "${pkgIndex}"
			done
		fi

		mkdir "${OUTDIR}/lib" || exit 1
		cp -r "${INSTDIR}/lib"/tk* "${OUTDIR}/lib/"
		cp -r "${INSTDIR}/bin"/tk*.dll "${OUTDIR}/lib/"/tk*/
		cp -r "${INSTDIR}/lib"/libtk* "${OUTDIR}/lib"/tk*/
		rm -rf "${OUTDIR}/lib"/tk*/demos

		"${STRIP:-strip}" -g "${OUTDIR}"/lib/tk*/*.{so,dll,dylib,shlib} >/dev/null 2>/dev/null
		find "${OUTDIR}" -type f -name '*.a' | xargs rm -f >/dev/null 2>/dev/null

		# If we have a shared object, delete static libraries
		if find "${INSTDIR}" -type f '(' -name '*.dll' -o -name '*.so' -o -name '*.dylib' -o -name '*.shlib' ')' 2>/dev/null | grep '^' >/dev/null; then
			find "${INSTDIR}" -type f -name '*.a' | grep -v 'stub' | xargs rm -f
		fi

		break
	done

	exit 0
) || exit 1

exit 0
