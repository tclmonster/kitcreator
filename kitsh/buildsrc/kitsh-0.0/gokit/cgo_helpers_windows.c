#ifdef _WIN32
/*
 * cgo_helpers_windows.c --
 *
 *	Windows-specific C shim for Go entry point.
 *	Adapted from winMain.c for use with cgo.
 *
 * Copyright (c) 1995-1997 Sun Microsystems, Inc.
 * Copyright (c) 1998-1999 by Scriptics Corporation.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 */

#include "config.h"
#include <tk.h>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#undef WIN32_LEAN_AND_MEAN
#include <malloc.h>

#ifndef UNDER_CE
#include <locale.h>
#endif

/*
 * Forward declarations for procedures defined later in this file:
 */

static void		setargv(int *argcPtr, char ***argvPtr);
static Tcl_PanicProc	WishPanic;

#ifndef TK_LOCAL_APPINIT
#define TK_LOCAL_APPINIT Tcl_AppInit
#endif
extern int TK_LOCAL_APPINIT(Tcl_Interp *interp);

#ifdef TK_LOCAL_MAIN_HOOK
extern int TK_LOCAL_MAIN_HOOK(int *argc, char ***argv);
#endif

extern int TclKit_AppInit(Tcl_Interp *interp);

/*
 *----------------------------------------------------------------------
 *
 * WishPanic --
 *
 *	Display a message and exit.
 *
 *----------------------------------------------------------------------
 */

void
WishPanic TCL_VARARGS_DEF(CONST char *,arg1)
{
    va_list argList;
    char buf[1024];
    CONST char *format;

    format = TCL_VARARGS_START(CONST char *,arg1,argList);
    vsprintf(buf, format, argList);

    MessageBeep(MB_ICONEXCLAMATION);
    MessageBox(NULL, buf, "Fatal Error in Wish",
	    MB_ICONSTOP | MB_OK | MB_TASKMODAL | MB_SETFOREGROUND);
#ifdef _MSC_VER
    DebugBreak();
#endif
    ExitProcess(1);
}

/*
 *-------------------------------------------------------------------------
 *
 * setargv --
 *
 *	Parse the Windows command line string into argc/argv.
 *
 *--------------------------------------------------------------------------
 */

static void
setargv(int *argcPtr, char ***argvPtr)
{
    char *cmdLine, *p, *arg, *argSpace;
    char **argv;
    int argc, size, inquote, copy, slashes;

    cmdLine = GetCommandLine();

    /*
     * Precompute an overly pessimistic guess at the number of arguments
     * in the command line by counting non-space spans.
     */

    size = 2;
    for (p = cmdLine; *p != '\0'; p++) {
	if ((*p == ' ') || (*p == '\t')) {
	    size++;
	    while ((*p == ' ') || (*p == '\t')) {
		p++;
	    }
	    if (*p == '\0') {
		break;
	    }
	}
    }
    argSpace = (char *) Tcl_Alloc(
	    (unsigned) (size * sizeof(char *) + strlen(cmdLine) + 1));
    argv = (char **) argSpace;
    argSpace += size * sizeof(char *);
    size--;

    p = cmdLine;
    for (argc = 0; argc < size; argc++) {
	argv[argc] = arg = argSpace;
	while ((*p == ' ') || (*p == '\t')) {
	    p++;
	}
	if (*p == '\0') {
	    break;
	}

	inquote = 0;
	slashes = 0;
	while (1) {
	    copy = 1;
	    while (*p == '\\') {
		slashes++;
		p++;
	    }
	    if (*p == '"') {
		if ((slashes & 1) == 0) {
		    copy = 0;
		    if ((inquote) && (p[1] == '"')) {
			p++;
			copy = 1;
		    } else {
			inquote = !inquote;
		    }
                }
                slashes >>= 1;
            }

            while (slashes) {
		*arg = '\\';
		arg++;
		slashes--;
	    }

	    if ((*p == '\0')
		    || (!inquote && ((*p == ' ') || (*p == '\t')))) {
		break;
	    }
	    if (copy != 0) {
		*arg = *p;
		arg++;
	    }
	    p++;
        }
	*arg = '\0';
	argSpace = arg + 1;
    }
    argv[argc] = NULL;

    *argcPtr = argc;
    *argvPtr = argv;
}

/*
 *----------------------------------------------------------------------
 *
 * cgo_call_winmain --
 *
 *	Performs the equivalent of WinMain() for use from Go.
 *	Sets up locale, parses command line, fixes argv[0], then
 *	calls Tk_Main.
 *
 *----------------------------------------------------------------------
 */

void cgo_call_winmain(void)
{
    char **argv;
    int argc;
#ifndef UNDER_CE
    char buffer[MAX_PATH+1];
    char *p;
#endif

    Tcl_SetPanicProc(WishPanic);

#ifndef UNDER_CE
    setlocale(LC_ALL, "C");
    setargv(&argc, &argv);

    /*
     * Replace argv[0] with full pathname of executable, and forward
     * slashes substituted for backslashes.
     */

    GetModuleFileName(NULL, buffer, sizeof(buffer));
    argv[0] = buffer;
    for (p = buffer; *p != '\0'; p++) {
	if (*p == '\\') {
	    *p = '/';
	}
    }
#else
    nCmdShow = SW_SHOWNORMAL;
    XCEShowWaitCursor();
    xceinit(GetCommandLine());
    argc = __xceargc;
    argv = __xceargv;
#endif

#ifdef TK_LOCAL_MAIN_HOOK
    TK_LOCAL_MAIN_HOOK(&argc, &argv);
#endif

    Tk_Main(argc, argv, TclKit_AppInit);
}
#endif /* _WIN32 */
