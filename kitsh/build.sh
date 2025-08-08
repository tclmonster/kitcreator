#! /usr/bin/env bash

if [ ! -f 'build.sh' ]; then
	echo 'ERROR: This script must be run from the directory it is in' >&2

	exit 1
fi
if [ -z "${TCLVERS}" ]; then
	echo 'ERROR: The TCLVERS environment variable is not set' >&2

	exit 1
fi

KITSHVERS="0.0"
BUILDDIR="$(pwd)/build/kitsh-${KITSHVERS}"
OUTDIR="$(pwd)/out"
INSTDIR="$(pwd)/inst"
OTHERPKGSDIR="$(pwd)/../"
export KITSHVERS BUILDDIR OUTDIR INSTDIR OTHERPKGSDIR

# Set configure options for this sub-project
LDFLAGS_ADD="${KC_KITSH_LDFLAGS_ADD}"
LDFLAGS="${LDFLAGS} ${KC_KITSH_LDFLAGS}"
CFLAGS="${CFLAGS} ${KC_KITSH_CFLAGS}"
CPPFLAGS="${CPPFLAGS} ${KC_KITSH_CPPFLAGS}"
LIBS="${LIBS} ${KC_KITSH_LIBS}"
export LDFLAGS_ADD LDFLAGS CFLAGS CPPFLAGS LIBS

if [ -z "${ENABLECOMPRESSION}" ]; then
	ENABLECOMPRESSION="1"
fi
export ENABLECOMPRESSION

rm -rf 'build' 'out' 'inst'
mkdir 'out' 'inst' || exit 1


(
	cp -rp 'buildsrc' 'build'
	cd "${BUILDDIR}" || exit 1

	# Fix up archives that Tcl gets wrong
	for archive in ../../../tcl/inst/lib/dde*/tcldde*.a ../../../tcl/inst/lib/reg*/tclreg*.a; do
		if [ ! -f "${archive}" ]; then
			continue
		fi

		rm -rf __TEMP__
		(
			mkdir __TEMP__ || exit 1
			cd __TEMP__

			## Patch archive name
			archive="../${archive}"

			"${AR:-ar}" x "${archive}" || exit 1

			rm -f "${archive}"

			"${AR:-ar}" cr "${archive}" *.o || exit 1
			"${RANLIB:-ranlib}" "${archive}" || true
		)
	done

	# Cleanup, just incase the incoming directory was not pre-cleaned
	${MAKE:-make} distclean >/dev/null 2>/dev/null
	rm -rf 'starpack.vfs'

	# Create VFS directory
	mkdir "starpack.vfs"
	mkdir "starpack.vfs/lib"

	## Install "boot.tcl"
	cp 'boot.tcl' 'starpack.vfs/'

	## Install "tclkit.ico"
	cp 'tclkit.ico' 'starpack.vfs/'

	## Copy in all built directories
	cp -r "${OTHERPKGSDIR}"/*/out/* 'starpack.vfs/'

	## Rename the "vfs" package directory to what "boot.tcl" expects
	mv 'starpack.vfs/lib'/vfs* 'starpack.vfs/lib/vfs'

	# Figure out if zlib compiled (if not, the system zlib will be used and we
	# will need to have that present)
	ZLIBDIR="$(cd "${OTHERPKGSDIR}/zlib/inst" 2>/dev/null && pwd)"
	export ZLIBDIR
	if [ -z "${ZLIBDIR}" -o ! -f "${ZLIBDIR}/lib/libz.a" ]; then
		unset ZLIBDIR
	fi

	# Copy user specified kit.rc and tclkit.ico in to build directory, if found
	cp "${KITCREATOR_ICON}" "${BUILDDIR}/tclkit.ico"
	cp "${KITCREATOR_RC}" "${BUILDDIR}/kit.rc"

	# Include extra objects as required
	## Initialize list of extra objects
	EXTRA_OBJS=""
	export EXTRA_OBJS

	## Tk Resources (needed for Win32 support) -- remove kit-found resources to prevent the symbols from being in conflict
	TKDIR="$(cd "${OTHERPKGSDIR}/tk/inst" 2>/dev/null && pwd)"
	if [ -n "${TKDIR}" ]; then
		TKRSRC="${TKDIR}/lib/tkbase.res.o"
		if [ -f "${TKRSRC}" ]; then
			EXTRA_OBJS="${EXTRA_OBJS} ${TKRSRC}"

			echo ' *** Removing "kit.rc" since we have Tk with its own resource file'

			rm -f "${BUILDDIR}/kit.rc"
		fi
	else
		# If Tk is present the "wish" manifest is copied when Tk is built (because
		# that is when the *.rc file is built). In the absense of Tk the "tclsh"
		# manifest is copied to ensure it is present for the kit.rc file.
		if [ -f "$KITCREATOR_DIR/tclkit.exe.manifest" ]; then
			KITCREATOR_MANIFEST="$KITCREATOR_DIR/tclkit.exe.manifest"
		else
			KITCREATOR_MANIFEST="$KITCREATOR_DIR/tcl/build/tcl${TCLVERS}/win/tclsh.exe.manifest"
		fi
		echo " *** Creating tclkit.exe.manifest from $KITCREATOR_MANIFEST"
		cat "${KITCREATOR_MANIFEST}" | sed 's@name="Tcl.tclsh"@name="Tcl.tclkit"@' >> ${BUILDDIR}/tclkit.exe.manifest
	fi

	# Cleanup
	rm -f kit kit.exe tclsh tclsh.exe

	# Determine if target is KitDLL or KitSH
	if [ "${KITTARGET}" = "kitdll" ]; then
		if [ "${KITCREATOR_STATIC_KITDLL}" = '1' ]; then
			CONFIGUREEXTRA="${CONFIGUREEXTRA} --enable-kitdll=static"
		else
			CONFIGUREEXTRA="${CONFIGUREEXTRA} --enable-kitdll"
		fi
	fi

	function codesign_requested() {
		test -n "${CODESIGN_SIGNATURE}"
	}

	function apply_signature() {
	    local path="$1"
	    local identifier="$2"
	    if test -z "${path}"; then
		    echo "No path provided to apply_signature"
		    exit 1
	    fi
	    if codesign_requested; then
		    codesign_extra=
		    if test -n "${CODESIGN_PREFIX}"; then
			    codesign_extra="${codesign_extra} --prefix ${CODESIGN_PREFIX}"
		    fi
		    if test -n "${identifier}"; then
			    codesign_extra="${codesign_extra} --identifier ${identifier}"
		    fi
		    printf '%s' "Signing \"$path\"... "
		    codesign --sign "${CODESIGN_SIGNATURE}" --force --options runtime --timestamp \
			     ${codesign_extra} \
			     "$path" >/dev/null 2>&1 || exit 1

		    if codesign --verify --deep --strict "${path}" 2>/dev/null; then
			    echo "success."
		    else
			    echo "verification failed."
			    exit 1
		    fi
	    fi
	}

	function strip_debug_symbols() {
	    ! echo " ${CONFIGUREEXTRA} " | grep -q ' --enable-symbols '
	}

	# Strip all binaries of unnecessary symbols and apply signature (if requested)
	if strip_debug_symbols; then

		# Strip debug symbols from shared libraries. First attempt to use the
		# Gnu strip-flag and fallback to the macOS strip-flag. On macOS it may be
		# Apple's version of strip or one supplied by a mac port toolchain (hence both
		# are possible).

		STRIP_FLAGS='--strip-debug'
		find ./starpack.vfs \( -name '*.dll' -o -name '*.so' -o -name '*.dylib' \) | while read -r file; do
			chmod +w "${file}"
			echo "Running: ${STRIP:-strip} ${STRIP_FLAGS} \"$file\""
			if ! "${STRIP:-strip}" ${STRIP_FLAGS} "$file"; then
				STRIP_FLAGS='-S'
				echo "Running: ${STRIP:-strip} ${STRIP_FLAGS} \"$file\""
				if ! "${STRIP:-strip}" ${STRIP_FLAGS} "$file"; then
					echo "Failed to strip debug symbols from \"$file\"."
					exit 1
				fi
			fi

			# All extensions must be signed prior to being added to the VFS
			apply_signature "${file}"
		done
	fi

	# Compile Kit
	if [ -z "${ZLIBDIR}" ]; then
		echo "Running: ./configure --with-tcl=\"${TCLCONFIGDIR}\" ${CONFIGUREEXTRA}"

		./configure --with-tcl="${TCLCONFIGDIR}" ${CONFIGUREEXTRA}
	else
		echo "Running: ./configure --with-tcl=\"${TCLCONFIGDIR}\" --with-zlib=\"${ZLIBDIR}\" ${CONFIGUREEXTRA}"

		./configure --with-tcl="${TCLCONFIGDIR}" --with-zlib="${ZLIBDIR}" ${CONFIGUREEXTRA}
	fi

	echo "Running: ${MAKE:-make}"
	${MAKE:-make} || exit 1

	# Fix up Win32 DLL names
	## .DLL.A -> .LIB
	for file in libtclkit*.dll.a; do
		if [ ! -f "${file}" ]; then
			continue
		fi

		newfile="$(basename "${file}" .dll.a).lib"
		mv "${file}" "${newfile}"
	done

	## .DLL.DEF -> .DEF
	for file in libtclkit*.dll.def; do
		if [ ! -f "${file}" ]; then
			continue
		fi

		newfile="$(basename "${file}" .dll.def).def"
		mv "${file}" "${newfile}"
	done

	# Determine name of created kit
	KITTARGET_NAME='__error__'
	if [ "${KITTARGET}" = "kitdll" ]; then
		## Find the library created
		for chkkittarget in libtclkit*.*; do
			if [ ! -f "${chkkittarget}" ]; then
				continue
			fi

			if echo "${chkkittarget}" | egrep '\.(lib|def|a)$'; then
				continue
			fi

			KITTARGET_NAME="./${chkkittarget}"

			break
		done

		## Build either tclsh or wish to bundle with KitDLL and
		## copy the target as "kit" so it may be run later.

		KITDLL_EXE_TARGET=tclsh
		if echo " ${KITCREATOR_PKGS} " | grep -q 'tk'; then
			KITDLL_EXE_TARGET=wish
		fi

		eval tclshExtraMakeArgs=(${KC_KITSH_TCLSH_EXTRA_MAKE_ARGS})

		echo "Running: ${MAKE:-make} ${KITDLL_EXE_TARGET} ${tclshExtraMakeArgs[@]}"
		${MAKE:-make} ${KITDLL_EXE_TARGET} "${tclshExtraMakeArgs[@]}"

		if [ -f "${KITDLL_EXE_TARGET}.exe" ]; then
			KITDLL_EXE_TARGET="${KITDLL_EXE_TARGET}.exe"
			cp ${KITDLL_EXE_TARGET} kit.exe
		else
			cp ${KITDLL_EXE_TARGET} kit
		fi

		apply_signature "${KITDLL_EXE_TARGET}"

		export KITDLL_EXE_TARGET ;# Allow this exe to be bundled for notarization (see below)

	else
		## The executable is always named "kit"
		if [ -f 'kit.exe' ]; then
			KITTARGET_NAME='./kit.exe'
		else
			KITTARGET_NAME='./kit'
		fi
	fi
	export KITTARGET_NAME

	if [ "${KITTARGET_NAME}" = '__error__' ]; then
		echo "Failed to locate kit target!" >&2

		exit 1
	fi

	# Intall VFS onto kit
	## Determine if we have a Tclkit to do this work
	TCLKIT="${TCLKIT:-tclkit}"
	if echo 'exit 0' | "${TCLKIT}" >/dev/null 2>/dev/null; then
		## Install using existing Tclkit
		### Call installer
		echo "Running: \"${TCLKIT}\" installvfs.tcl \"${KITTARGET_NAME}\" starpack.vfs \"${ENABLECOMPRESSION}\" \"${KITTARGET_NAME}.new\""
		"${TCLKIT}" installvfs.tcl "${KITTARGET_NAME}" starpack.vfs "${ENABLECOMPRESSION}" "${KITTARGET_NAME}.new" || exit 1
	else
		if echo 'exit 0' | "${KITTARGET_NAME}" >/dev/null 2>/dev/null; then
			## Bootstrap (cannot cross-compile)
			### Call installer
			echo "set argv [list {${KITTARGET_NAME}} starpack.vfs {${ENABLECOMPRESSION}} {${KITTARGET_NAME}.new}]" > setup.tcl
			echo 'if {[catch { clock seconds }]} { proc clock args { return 0 } }' >> setup.tcl
			echo 'source installvfs.tcl' >> setup.tcl

			echo 'Running: echo | \"${KITTARGET_NAME}\" setup.tcl'
			echo | "${KITTARGET_NAME}" setup.tcl || exit 1
		else
			## Install using Tclsh, which may work if we're not using Metakit
			### Call installer
			echo "Running: \"${TCLSH_NATIVE}\" installvfs.tcl \"${KITTARGET_NAME}\" starpack.vfs \"${ENABLECOMPRESSION}\" \"${KITTARGET_NAME}.new\""
			"${TCLSH_NATIVE}" installvfs.tcl "${KITTARGET_NAME}" starpack.vfs "${ENABLECOMPRESSION}" "${KITTARGET_NAME}.new" || exit 1
		fi
	fi

	cp "${KITTARGET_NAME}.new" "${KITTARGET_NAME}"
	rm -f "${KITTARGET_NAME}.new"

	if strip_debug_symbols; then
		case "${KITTARGET_NAME}" in
			./kit*)
				echo "Running: ${STRIP:-strip} ${KITTARGET_NAME}"
				if ! "${STRIP:-strip}" ${KITTARGET_NAME}; then
					echo "Failed to strip debug symbols from \"${KITTARGET_NAME}\""
					exit 1
				fi
				;;

			*)
				echo "Running: ${STRIP:-strip} ${STRIP_FLAGS} ${KITTARGET_NAME}"
				if ! "${STRIP:-strip}" ${STRIP_FLAGS} "$file"; then
					echo "Failed to strip debug symbols from \"${KITTARGET_NAME}\"."
					exit 1
				fi
		esac
	fi

	apply_signature "${KITTARGET_NAME}" "${CODESIGN_KITSH_IDENTIFIER:-}"

	# Package all binaries for notarization on macOS. This requires CVFS because notarization
	# will fail when data is appended to the binary.
	if test codesign_requested -a "${KC_KITSTORAGE}" = "cvfs"; then
		export kitsh_libfiles=$(find ./starpack.vfs \( -name '*.so' -o -name '*.dylib' \))
		export kitsh_exe=${KITTARGET_NAME}
		export notarydir="tclkit-notarize-$(openssl dgst -sha256 "$kitsh_exe" | cut -d' ' -f2)"
		export notaryzip="${KITCREATOR_DIR}/${notarydir}.zip"

		echo '
		     if {[file exists $env(notarydir)]} {
			     file delete -force $env(notarydir)
		     }
		     file mkdir $env(notarydir)
		     file copy $env(kitsh_exe) $env(notarydir)
		     foreach file [lmap li $env(kitsh_libfiles) {expr { $li eq "" ? [continue] : [string trim $li]}}] {
			     set dst [file join $env(notarydir) [string range $file [string length "./starpack.vfs/"] end]]
			     file mkdir [file dirname $dst]
			     file copy $file $dst
		     }
		     if {[info exists env(KITDLL_EXE_TARGET)]} {
		     	     file copy $env(KITDLL_EXE_TARGET) $env(notarydir)
		     }
		     exec zip -r $env(notaryzip) $env(notarydir)
		     file delete -force $env(notarydir)

		' | "${TCLSH_NATIVE:-tclsh}" || exit 1
	fi

	# Cleanup
	if [ "${KITTARGET}" = "kitdll" ]; then
		## Remove built interpreters if we are building KitDLL --
		## they're just tiny stubs anyway
		rm -f kit kit.exe
	fi

	exit 0
) || exit 1

exit 0
