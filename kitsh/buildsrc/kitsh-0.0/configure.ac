dnl What are we running
AC_INIT([kitsh],[0.0])

AC_ARG_WITH(tclsh, [  --with-tclsh=FILE location of a working tclsh executable], with_tclsh=${withval})

SC_SIMPLE_EXEEXT

# allow user to override the tclsh we think we found
if test x"${with_tclsh}" != x ; then
    AC_MSG_CHECKING([for tclsh])
    if echo 'exit 0' | "${with_tclsh}" >/dev/null 2>/dev/null
    then
        TCLSH_PROG=${with_tclsh}
        AC_MSG_RESULT([$TCLSH_PROG, via --with-tclsh])
    else
        AC_MSG_ERROR([Bad --with-tclsh ${with_tclsh}, not found or not executable])
    fi
    AC_SUBST(TCLSH_PROG)

elif test x"${TCLSH_NATIVE}" != x ; then
    AC_MSG_CHECKING([for tclsh])
    if echo 'exit 0' | "${TCLSH_NATIVE}" >/dev/null 2>/dev/null
    then
        TCLSH_PROG=${TCLSH_NATIVE}
        AC_MSG_RESULT([$TCLSH_PROG, via TCLSH_NATIVE environment variable])
    else
        AC_MSG_ERROR([Bad TCLSH_NATIVE ${TCLSH_NATIVE}, not found or not executable])
    fi
    AC_SUBST(TCLSH_PROG)

else
    SC_PROG_TCLSH
fi

dnl Checks for programs.
AC_PROG_CC
AC_PROG_MAKE_SET
AC_PROG_INSTALL
AC_CHECK_TOOL(AR, ar, ar)
AC_PROG_RANLIB
AC_USE_SYSTEM_EXTENSIONS
AC_USE_SYSTEM_EXTENSIONS

dnl Check for Go compiler (optional, for Go entry points)
AC_ARG_WITH(go, AS_HELP_STRING([--with-go], [enable Go entry points (default: auto-detect)]), [
	with_go="${withval}"
], [
	with_go="auto"
])

if test "${with_go}" = "no"; then
	HAVE_GO=no
	AC_MSG_CHECKING([for Go compiler])
	AC_MSG_RESULT([disabled by --without-go])
else
	AC_MSG_CHECKING([for Go compiler])
	AC_ARG_VAR([GO], [Path to Go compiler])
	if test "${with_go}" != "yes" -a "${with_go}" != "auto"; then
		GO="${with_go}"
	fi
	if test -z "$GO"; then
	    AC_PATH_PROG([GO], [go], [no])
	fi
	if test "x$GO" != "xno"; then
	    dnl Auto-detect GOROOT for distro-packaged Go (e.g. MSYS2) where the
	    dnl binary is not at $GOROOT/bin/go and self-location is disabled.
	    if test -z "$GOROOT"; then
	        _go_bindir=`AS_DIRNAME(["$GO"])`
	        for _try_goroot in "${_go_bindir}/../lib/go" "${_go_bindir}/.."; do
	            if test -d "${_try_goroot}/src/runtime"; then
	                GOROOT=`cd "${_try_goroot}" && pwd`
	                export GOROOT
	                break
	            fi
	        done
	    fi
	    go_version=`$GO version 2>&1`
	    if test $? -eq 0; then
	        HAVE_GO=yes
	        AC_MSG_RESULT([$GO ($go_version)])
	    else
	        HAVE_GO=no
	        if test "${with_go}" != "auto"; then
	            AC_MSG_ERROR([Go compiler $GO does not work: $go_version])
	        fi
	        AC_MSG_RESULT([found $GO but it does not work: $go_version])
	    fi
	else
	    HAVE_GO=no
	    if test "${with_go}" != "auto"; then
	        AC_MSG_ERROR([Go compiler not found (requested via --with-go)])
	    fi
	    AC_MSG_RESULT([not found, Go entry points disabled])
	fi
fi
AC_SUBST(GO)
AC_SUBST(GOROOT)
AC_SUBST(HAVE_GO)
GO_BUILD_TAGS=""

dnl Find out if we should build a DLL or an Executable
TARGET="tclkit"
EXTRA_KIT_DEPS=""
AC_MSG_CHECKING([what target to build])
AC_ARG_ENABLE(kitdll, AS_HELP_STRING([--enable-kitdll],[Enable building KitDLL instead of Tclkit (default: no)]), [
	AS_CASE([$enableval],
		[yes|kitdll], [
			TARGET="kitdll"
		],
		static, [
			TARGET="kitdll-static"
		],
		no, [
			true
		], [
			AC_MSG_RESULT([unknown])

			AC_MSG_ERROR([Invalid option: $enableval])
		]
	)
])
AC_MSG_RESULT([$TARGET])
AC_SUBST(TARGET)

dnl Find the appropriate libraries to link to
AC_SEARCH_LIBS(acos, m,, [ AC_MSG_WARN([Couldn't find acos (normally in libm)!]) ])
AC_SEARCH_LIBS(dlsym, dl,, [ AC_MSG_WARN([Couldn't find dlsym (normally in libdl)!]) ])

AS_IF([test "$TARGET" = "tclkit"], [
	dnl We have Tclkit
	TARGET_BASE='tclkit'

	dnl Specify local Appinit function
	AC_DEFINE(TK_LOCAL_APPINIT, [TclKit_AppInit], [Tclkit appinit function])

], [
	dnl We have KitDLL
	TARGET_BASE='kitdll'

	dnl Determine system information
	DC_CHK_OS_INFO

	dnl Determine how to create a shared object
	DC_GET_SHOBJFLAGS

	dnl Determine if we have "objcopy" available to weaken non-Tcl/Tk symbols
	AC_CHECK_TOOL(OBJCOPY, objcopy, [:])

	dnl Define KitDLL usage
	AC_DEFINE([TCLKIT_DLL], [1], [Define if you are using a KitDLL rather than a Tclkit])

	dnl Define a static KitDLL
	AS_IF([test "$TARGET" = "kitdll-static"], [
		AC_CHECK_TOOL(RANLIB, [ranlib], [:])
		AC_CHECK_TOOL(AR, [ar], [false MISSING AR])

		AC_DEFINE([TCLKIT_DLL_STATIC], [1], [Define if you are building a static KitDLL])
	])
])

dnl Figure out how to statically link to libgcc, if needed
DC_STATIC_LIBGCC

dnl Set linker rpath for tclsh/wish
DC_SETLDRUNPATH([.])

dnl Find the appropriate Tcl headers and libraries
DC_DO_TCL

dnl Find archives we need to link to
DC_FIND_TCLKIT_LIBS

dnl Find extra objects we need to link as a part of "kit"
AC_SUBST(EXTRA_OBJS)
AC_SUBST(EXTRA_VFS_OBJS)

dnl Check for Windows Resource Compiler
AC_CHECK_TOOL([RC], [windres], [false])

dnl If we found the resource compiler, add "kit.res.o" to our list of objects to build
dnl (as long as the source for such an object exists)
AS_IF([test "$RC" != "false"], [
	AS_IF([test "$host_os" = "mingw32msvc" -o "$host_os" = "mingw32"], [
		AS_IF([test -f kit.rc], [
			EXTRA_OBJS="$EXTRA_OBJS kit.res.o"
		])
	])
])

dnl Check for Tcl features
SAVE_LIBS="${LIBS}"
LIBS="${ARCHS} ${LIBS}"

dnl Determine if we have "Tcl_SetStartupScript" (8.6.x) or "TclSetStartupScriptPath" (8.4.x)
AC_CHECK_FUNCS(Tcl_SetStartupScript TclSetStartupScriptPath)

dnl Check for the ability to get the current system encoding
AC_CHECK_FUNCS(Tcl_GetEncodingNameFromEnvironment Tcl_SetSystemEncoding)
LIBS="${SAVE_LIBS}"

dnl Check for optional headers
AC_CHECK_HEADERS(unistd.h string.h strings.h)

dnl Check for optional system calls
AC_CHECK_FUNCS(readlink)

dnl Check for acceptable dladdr so we can find ourselves on Solaris
DC_CHECK_FOR_ACCEPTABLE_DLADDR

dnl Find zlib
AC_ARG_WITH(zlib, AS_HELP_STRING([--with-zlib],[directory containing zlib]), [
	CPPFLAGS="${CPPFLAGS} -I${with_zlib}/include -I${with_zlib}"
	CFLAGS="${CFLAGS} -I${with_zlib}/include -I${with_zlib}"
	LDFLAGS="${LDFLAGS} -L${with_zlib}/lib -L${with_zlib}"
])

dnl Only needed for Tclkit
DC_DO_STATIC_LINK_LIB(zlib, -lz,, [
	DC_DO_STATIC_LINK_LIB(zlib, -lzlib,, [
		AC_SEARCH_LIBS(inflate, z zlib,, [
			AC_MSG_WARN([Couldn't find inflate (normally in zlib)!])
		])
	])
])

dnl Determine which storage mechanism to use
AC_MSG_CHECKING([which Tclkit Storage mechanism to use])

storage_mech="auto"
AC_ARG_ENABLE(kit-storage, AS_HELP_STRING([--enable-kit-storage={zip|mk4|cvfs}],[Specify storage mechanism to use for built-in VFS (default: auto)]), [
	AS_CASE(["$enableval"],
		mk4, [
			storage_mech="mk4"
		],
		zip, [
			storage_mech="zip"
		],
		cvfs, [
			storage_mech="cvfs"
		],
		yes, [
			# If they just want to enable kit storage, but nothing specifically, do nothing
			storage_mech="auto"
		],
		auto, [
			# Auto is how it works by default
			storage_mech="auto"
		],
		no, [
			# You can't disable kit storage
			AC_MSG_RESULT([fail])
			AC_MSG_ERROR([Kit Storage cannot be disabled])
		],
		[
			AC_MSG_RESULT([fail])
			AC_MSG_ERROR([Unknown kit storage type: $enableval])
		]
	)
])

dnl Explicitly define the storage mechanism
AS_IF([test "$storage_mech" = "auto"], [
	AS_IF([test "$TARGET" = 'tclkit'], [
		AS_IF([test "x$kc_cv_feature_kit_includes_mk4tcl" = 'x1'], [
			storage_mech="mk4"
		], [
			storage_mech="zip"
		])
	], [
		storage_mech="cvfs"
	])
])

dnl Note result
AC_MSG_RESULT([$storage_mech])

dnl Define appropriate macros for the storage mechanism
AS_CASE([$storage_mech],
	mk4, [
		AC_DEFINE([KIT_STORAGE_MK4], [1], [Define if you are going to use Metakit4 for kit storage])
	],
	zip, [
		AC_DEFINE([KIT_STORAGE_ZIP], [1], [Define if you are going to use ZIP for kit storage])

		dnl Add appropriate dependencies
		EXTRA_KIT_DEPS="zipvfs.tcl.h"
	],
	cvfs, [
		AC_DEFINE([KIT_STORAGE_CVFS], [1], [Define if you are going to use C-VFS for kit storage])

		dnl Define that C-VFS should be make [load]-able
		AC_DEFINE([CVFS_MAKE_LOADABLE], [1], [Specify that the C-VFS should be able to be loaded])

		dnl Add appropriate dependencies
		EXTRA_KIT_DEPS="cvfs.tcl.h"
		EXTRA_VFS_OBJS="${EXTRA_VFS_OBJS} cvfs_data_tcl.o"

		dnl Set any flags as required
		DC_SET_DIR2C_FLAGS
	]
)

AC_SUBST(EXTRA_KIT_DEPS)
AC_SUBST(LDFLAGS_ADD)

dnl Put correct Makefile template in place
rm -f Makefile.in
cp Makefile.${TARGET_BASE}.in Makefile.in

AC_SUBST(GO_BUILD_TAGS)

dnl Produce output
AC_CONFIG_FILES([Makefile Makefile.common])
AC_OUTPUT
