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

SRC="src/tcl${TCLVERS}.tar.gz"
SRCURL="http://prdownloads.sourceforge.net/tcl/tcl${TCLVERS}-src.tar.gz"
SRCHASH='-'
BUILDDIR="$(pwd)/build/tcl${TCLVERS_CLEAN}"
OUTDIR="$(pwd)/out"
INSTDIR="$(pwd)/inst"
PATCHSCRIPTDIR="$(pwd)/patchscripts"
PATCHDIR="$(pwd)/patches"
export SRC SRCURL BUILDDIR OUTDIR INSTDIR PATCHSCRIPTDIR PATCHDIR

case "${TCLVERS}" in
	8.6.4)
		SRCHASH='9e6ed94c981c1d0c5f5fefb8112d06c6bf4d050a7327e95e71d417c416519c8d'
		;;
	8.6.5)
		SRCHASH='ce26d5b9c7504fc25d2f10ef0b82b14cf117315445b5afa9e673ed331830fb53'
		;;
	8.6.6)
		SRCHASH='a265409781e4b3edcc4ef822533071b34c3dc6790b893963809b9fe221befe07'
		;;
	8.6.7)
		SRCHASH='7c6b8f84e37332423cfe5bae503440d88450da8cc1243496249faa5268026ba5'
		;;
	8.6.8)
		SRCHASH='c43cb0c1518ce42b00e7c8f6eaddd5195c53a98f94adc717234a65cbcfd3f96a'
		;;
	8.6.9)
		SRCHASH='ad0cd2de2c87b9ba8086b43957a0de3eb2eb565c7159d5f53ccbba3feb915f4e'
		;;
	8.6.10)
		SRCHASH='5196dbf6638e3df8d5c87b5815c8c2b758496eb6f0e41446596c9a4e638d87ed'
		;;
	8.6.11)
		SRCHASH='8c0486668586672c5693d7d95817cb05a18c5ecca2f40e2836b9578064088258'
		;;
	8.6.12)
		SRCHASH='26c995dd0f167e48b11961d891ee555f680c175f7173ff8cb829f4ebcde4c1a6'
		;;
	8.6.13)
		SRCHASH='43a1fae7412f61ff11de2cfd05d28cfc3a73762f354a417c62370a54e2caf066'
		;;
	8.6.14)
		SRCHASH='5880225babf7954c58d4fb0f5cf6279104ce1cd6aa9b71e9a6322540e1c4de66'
		;;
	8.6.15)
		SRCHASH='861e159753f2e2fbd6ec1484103715b0be56be3357522b858d3cbb5f893ffef1'
		;;
	8.6.16)
		SRCHASH='91cb8fa61771c63c262efb553059b7c7ad6757afa5857af6265e4b0bdc2a14a5'
		;;
esac

KC_TCL_SQLITE_VEC="${KC_TCL_SQLITE_VEC:-0}"

SQLITE_VEC_VER='0.1.7-alpha.2'
SQLITE_VEC_SRC="src/sqlite-vec-${SQLITE_VEC_VER}-amalgamation.tar.gz"
SQLITE_VEC_SRCURL="https://github.com/asg017/sqlite-vec/releases/download/v${SQLITE_VEC_VER}/sqlite-vec-${SQLITE_VEC_VER}-amalgamation.tar.gz"
SQLITE_VEC_SRCHASH='e3e563af0c312f6083b557f01ca985a124bde784b84f4add2f276d94aac25d07'

# Set configure options for this sub-project
LDFLAGS="${LDFLAGS} ${KC_TCL_LDFLAGS}"
CFLAGS="${CFLAGS} ${KC_TCL_CFLAGS}"
CPPFLAGS="${CPPFLAGS} ${KC_TCL_CPPFLAGS}"
LIBS="${LIBS} ${KC_TCL_LIBS}"
export LDFLAGS CFLAGS CPPFLAGS LIBS

rm -rf 'build' 'out' 'inst'
mkdir 'build' 'out' 'inst' || exit 1

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

		FOSSILTAG=$(echo "${TCLVERS}" | sed 's/^fossil_//g;s/_tk=.*$//g')
	fi
	export FOSSILTAG

	if [ -d 'buildsrc' ]; then
		# Override here to avoid downloading tarball from Fossil if we
		# have a particular tree already available.
		use_fossil='0'
	fi

	if [ "${use_fossil}" = "1" ]; then
		(
			cd src || exit 1

			workdir="tmp-$$${RANDOM}${RANDOM}${RANDOM}"
			rm -rf "${workdir}"

			mkdir "${workdir}" || exit 1
			cd "${workdir}" || exit 1

			# Handle Tcl first, since it will be used to base other packages on
			download "http://core.tcl.tk/tcl/tarball/tcl-fossil.tar.gz?uuid=${FOSSILTAG}" "tmp-tcl.tar.gz" - || rm -f 'tmp-tcl.tar.gz'
			gzip -dc 'tmp-tcl.tar.gz' | tar -xf -
			mv "tcl-fossil" "tcl${TCLVERS_CLEAN}"

			# Determine date of this Tcl release and use that date for all other dependent packages
			## Unless the release we are talking about is "trunk", in which case we use that everywhere
			if [ "${FOSSILTAG}" = "trunk" ]; then
				FOSSILDATE="${FOSSILTAG}"
			else
				FOSSILDATE="$(echo 'cd "tcl'"${TCLVERS_CLEAN}"'"; set file [lindex [glob *] 0]; file stat $file finfo; set date $finfo(mtime); set date [expr {$date + 1}]; puts [clock format $date -format {%Y-%m-%dT%H:%M:%S}]' | TZ='UTC' "${TCLSH_NATIVE}")"
			fi

			## If we are unable to determine the modification date, fall-back to the tag and hope for the best
			if [ -z "${FOSSILDATE}" ]; then
				FOSSILDATE="${FOSSILTAG}"
			fi

			# Handle other packages
			download "http://core.tcl.tk/itcl/tarball/itcl-fossil.tar.gz?uuid=${FOSSILDATE}" "tmp-itcl.tar.gz" - || rm -f 'tmp-itcl.tar.gz'
			download "http://core.tcl.tk/thread/tarball/thread-fossil.tar.gz?uuid=${FOSSILDATE}" "tmp-thread.tar.gz" - || rm -f "tmp-thread.tar.gz"
			download "http://core.tcl.tk/tclconfig/tarball/tclconfig-fossil.tar.gz?uuid=${FOSSILDATE}" "tmp-tclconfig.tar.gz" - || rm -f "tmp-tclconfig.tar.gz"
			if [ "${FOSSILDATE}" = "trunk" ] || [ "$(echo "${FOSSILDATE}" | cut -f 1 -d '-')" -ge '2012' ]; then
				_USE_TDBC='1'
				_USE_SQLITE='1'
				SQLITEVERS='3071401'
			fi

			if [ "${_USE_TDBC}" = '1' ]; then
				download "http://core.tcl.tk/tdbc/tarball/tdbc-fossil.tar.gz?uuid=${FOSSILDATE}" "tmp-tdbc.tar.gz" - || rm -f "tmp-tdbc.tar.gz"
			fi

			if [ "${_USE_SQLITE}" = '1' ]; then
				download "http://www.sqlite.org/sqlite-autoconf-${SQLITEVERS}.tar.gz" "tmp-sqlite3.tar.gz" - || rm -f "tmp-sqlite3.tar.gz"
			fi

			gzip -dc "tmp-itcl.tar.gz" | tar -xf -
			gzip -dc "tmp-thread.tar.gz" | tar -xf -
			gzip -dc "tmp-tclconfig.tar.gz" | tar -xf -

			mkdir -p "tcl${TCLVERS_CLEAN}/pkgs/" >/dev/null 2>/dev/null
			mv "itcl-fossil" "tcl${TCLVERS_CLEAN}/pkgs/itcl"
			mv "thread-fossil" "tcl${TCLVERS_CLEAN}/pkgs/thread"
			cp -r "tclconfig-fossil" "tcl${TCLVERS_CLEAN}/pkgs/itcl/tclconfig"
			cp -r "tclconfig-fossil" "tcl${TCLVERS_CLEAN}/pkgs/thread/tclconfig"
			mv "tclconfig-fossil" "tcl${TCLVERS_CLEAN}/tclconfig"

			if [ "${_USE_TDBC}" = '1' ]; then
				gzip -dc "tmp-tdbc.tar.gz" | tar -xf -
				mv "tdbc-fossil/tdbc" "tcl${TCLVERS_CLEAN}/pkgs/tdbc"
				mv "tdbc-fossil/tdbcsqlite3" "tcl${TCLVERS_CLEAN}/pkgs/tdbcsqlite3"
			fi

			if [ "${_USE_SQLITE}" = '1' ]; then
				gzip -dc "tmp-sqlite3.tar.gz" | tar -xf -

				mv "sqlite-autoconf-${SQLITEVERS}" sqlite-fossil
				(
					cd sqlite-fossil || exit

					mv sqlite3.c tea/generic/
					for file in *; do
						if [ "${file}" = "tea" ]; then
							continue
						fi

						rm -f "${file}"
					done
					mv tea/* .
					rmdir tea

					sed 's@\.\./\.\./sqlite3\.c@./sqlite3.c@' generic/tclsqlite3.c > generic/tclsqlite3.c.new
					cat generic/tclsqlite3.c.new > generic/tclsqlite3.c
					rm -f generic/tclsqlite3.c.new
				)
				mv sqlite-fossil "tcl${TCLVERS_CLEAN}/pkgs/sqlite3" >/dev/null 2>/dev/null
			fi

			tar -cf - "tcl${TCLVERS_CLEAN}" | gzip -c > "../../${SRC}"
			echo "${FOSSILDATE}" > "../../${SRC}.date"

			cd ..

			rm -rf "${workdir}"
		) || exit 1
	else
		if [ ! -d 'buildsrc' ]; then
			download "${SRCURL}" "${SRC}" "${SRCHASH}" || (
				echo '  Unable to download source code for Tcl.' >&4
				echo '  Aborting Tcl -- further packages will likely also fail.' >&4

				exit 1
			) || exit 1
		fi
	fi
fi

if [ "${KC_TCL_SQLITE_VEC}" = "1" ]; then
	download "${SQLITE_VEC_SRCURL}" "${SQLITE_VEC_SRC}" "${SQLITE_VEC_SRCHASH}" || (
		echo '  Unable to download source code for sqlite-vec.' >&4
		echo '  Aborting Tcl...' >&4
		exit 1
	) || exit 1
fi

(
	cd 'build' || exit 1

	if [ ! -d '../buildsrc' ]; then
		gzip -dc "../${SRC}" | tar -xf -
	else
		cp -rp ../buildsrc/* './'
	fi

	if [ -f "../${SQLITE_VEC_SRC}" ]; then
		gzip -dc "../${SQLITE_VEC_SRC}" | tar -xf -

		# Fix type redefinitions affecting amalgamation.
		patch -p1 <<'EOF'
diff -ruN A/sqlite-vec.c B/sqlite-vec.c
--- A/sqlite-vec.c	2025-01-10 19:18:50.000000000 -0400
+++ B/sqlite-vec.c	2025-05-05 09:56:30.383237900 -0300
@@ -73,13 +73,7 @@
 #endif
 #endif
 
-typedef int8_t i8;
-typedef uint8_t u8;
-typedef int16_t i16;
 typedef int32_t i32;
-typedef sqlite3_int64 i64;
-typedef uint32_t u32;
-typedef uint64_t u64;
 typedef float f32;
 typedef size_t usize;
EOF

		SQLITE_VEC_DST=$(cd "${BUILDDIR}"/pkgs/sqlite*/compat/sqlite3; pwd;)

		echo "Appending sqlite-vec.c to sqlite amalgamation..."
		cat sqlite-vec.c >> "${SQLITE_VEC_DST}"/sqlite3.c || exit 1

		echo "Appending vec_extra_init to sqlite amalgamation..."
		cat <<'EOF' >> "${SQLITE_VEC_DST}"/sqlite3.c || exit 1
/* Bridge function for the SQLITE_EXTRA_INIT mechanism */
int vec_extra_init(const char*) {
  /* We'll use this to register the extension for auto-loading */
  int rc = SQLITE_OK;

  /* Register the vec extension to be auto-loaded with each new connection */
  rc = sqlite3_auto_extension((void(*)(void))sqlite3_vec_init);

  return rc;
}
EOF
		echo "Copying sqlite-vec.h..."
		cp -f sqlite-vec.h "${SQLITE_VEC_DST}"/sqlite-vec.h

		export CFLAGS="${CFLAGS} -DSQLITE_EXTRA_INIT=vec_extra_init -DSQLITE_CORE"
	fi

	cd "${BUILDDIR}" || exit 1

	# Apply patches if needed
	for patch in "${PATCHDIR}/all"/tcl-${TCLVERS}-*.diff "${PATCHDIR}/all"/tcl-all-*.diff "${PATCHDIR}/${TCLVERS}"/tcl-${TCLVERS}-*.diff; do
		if [ ! -f "${patch}" ]; then
			continue
		fi
                
		echo "Applying: ${patch}"
		${PATCH:-patch} -p1 < "${patch}"
	done


	# Apply patch scripts if needed
	for patchscript in "${PATCHSCRIPTDIR}"/*.sh; do
		if [ -f "${patchscript}" ]; then
			echo "Running patch script: ${patchscript}"

			(
				. "${patchscript}"
			)
		fi
	done

	tryfirstdir=''
	case "${KC_CROSSCOMPILE_HOST_OS}" in
		*-*-darwin*)
			# Cross-compiling for Mac OS X -- try to build macosx directory first
			tryfirstdir='macosx'
			;;
		*-*-*)
			# Cross-compiling, do not assume based on build platform
			;;
		'')
			# Not cross-compiling, assume based on build platform
			if [ "$(uname -s)" = "Darwin" ]; then
				# Compiling for Mac OS X, build in that directory first
				tryfirstdir='macosx'
			fi
			;;
	esac
		
	for dir in "${tryfirstdir}" unix win macosx __fail__; do
		if [ -z "${dir}" ]; then
			continue
		fi

		if [ "${dir}" = "__fail__" ]; then
			# If we haven't figured out how to build it, reject.

			exit 1
		fi

		# Remove previous directory's "tclConfig.sh" if found
		rm -f 'tclConfig.sh'

		echo "Working in: $dir"
		cd "${BUILDDIR}/${dir}" || exit 1

		# Remove broken pre-generated Makfiles
		rm -f GNUmakefile Makefile makefile

		echo "Running: ./configure --disable-shared --with-encoding=utf-8 --prefix=\"${INSTDIR}\" --libdir=\"${INSTDIR}/lib\" ${CONFIGUREEXTRA}"
		./configure --disable-shared --with-encoding=utf-8 --prefix="${INSTDIR}" --libdir="${INSTDIR}/lib" ${CONFIGUREEXTRA}

		echo "Running: ${MAKE:-make}"
		${MAKE:-make} || continue

		private_headers=
		if echo " ${CONFIGUREEXTRA} " | grep ' --enable-tcl-private-headers ' \
				> /dev/null 2>&1; then

			private_headers=install-private-headers
		fi

		echo "Running: ${MAKE:-make} install $private_headers"
		${MAKE:-make} install $private_headers || (
			# Work with Tcl 8.6.x's TCLSH_NATIVE solution for
			# cross-compile installs

			echo "Running: ${MAKE:-make} install $private_headers TCLSH_NATIVE=\"${TCLSH_NATIVE}\""
			${MAKE:-make} install $private_headers TCLSH_NATIVE="${TCLSH_NATIVE}"
		) || (
			# Make install can fail if cross-compiling using Tcl 8.5.x
			# because the Makefile calls "$(TCLSH)".  We can't simply
			# redefine TCLSH because it also uses TCLSH as a build target
			sed 's@^$(TCLSH)@blah@' Makefile > Makefile.new
			cat Makefile.new > Makefile
			rm -f Makefile.new

			echo "Running: ${MAKE:-make} install $private_headers TCLSH=\"../../../../../../../../../../../../../../../../../$(which "${TCLSH_NATIVE}")\""
			${MAKE:-make} install $private_headers TCLSH="../../../../../../../../../../../../../../../../../$(which "${TCLSH_NATIVE}")"
		) || (
			# Make install can fail if cross-compiling using Tcl 8.5.9
			# because the Makefile calls "${TCL_EXE}".  We can't simply
			# redefine TCL_EXE because it also uses TCL_EXE as a build target
			sed 's@^${TCL_EXE}@blah@' Makefile > Makefile.new
			cat Makefile.new > Makefile
			rm -f Makefile.new

			echo "Running: ${MAKE:-make} install $private_headers TCL_EXE=\"../../../../../../../../../../../../../../../../../$(which "${TCLSH_NATIVE}")\""
			${MAKE:-make} install $private_headers TCL_EXE="../../../../../../../../../../../../../../../../../$(which "${TCLSH_NATIVE}")"
		) || exit 1

		mkdir "${OUTDIR}/lib" || exit 1
		cp -r "${INSTDIR}/lib"/* "${OUTDIR}/lib/"
		rm -rf "${OUTDIR}/lib/pkgconfig"
		rm -f "${OUTDIR}"/lib/* >/dev/null 2>/dev/null
		find "${OUTDIR}" -name '*.a' | xargs rm -f >/dev/null 2>/dev/null

		# Remove archive files that are just stubs for other files
		echo "Deleting these files from install directory:"
		find "${INSTDIR}" -name '*.a' ! -name '*stub*' | while IFS='' read -r filename; do
			dirname="$(dirname "${filename}")"

			delete='0'
			for dll in "${dirname}"/*.dll; do
				if [ -f "${dll}" ]; then
					delete='1'

					break
				fi
			done

			if [ "${delete}" = '1' ]; then
				echo "        ${filename}"

				rm -f "${filename}"
			fi
		done

		# Clean up packages that are not needed
		if [ -n "${KITCREATOR_MINBUILD}" ]; then
			find "${OUTDIR}" -name "tcltest*" -type d | xargs rm -rf
		fi

		# Clean up encodings
		if [ -n "${KITCREATOR_MINENCODINGS}" ]; then
			KEEPENCODINGS=" ascii.enc cp1252.enc iso8859-1.enc iso8859-15.enc iso8859-2.enc koi8-r.enc macRoman.enc "
			export KEEPENCODINGS
			find "${OUTDIR}/lib" -name 'encoding' -type d | while read encdir; do
				(
					cd "${encdir}" || exit 1

					for file in *; do
						if echo " ${KEEPENCODINGS} " | grep " ${file} " >/dev/null; then
							continue
						fi

						rm -f "${file}"
					done
				)
			done
		fi

		break
	done
) || exit 1

exit 0
