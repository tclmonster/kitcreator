#ifndef GOTEST_H
#define GOTEST_H

#include <tcl.h>
#include <stdlib.h>

/* Tcl 9 compatibility: Tcl_Size type for 64-bit lengths */
#ifndef TCL_SIZE_MAX
#  ifndef Tcl_Size
     typedef int Tcl_Size;
#  endif
#  define TCL_SIZE_MAX INT_MAX
#  define TCL_SIZE_MODIFIER ""
#endif

typedef Tcl_Obj *const *Tcl_ObjArgs;

DLLEXPORT int GotestHelloObjCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);

/*
 * Wrapper for Tcl_CreateObjCommand to unify the ClientData type
 * difference between Tcl 8 (ClientData) and Tcl 9 (void *).
 */
static inline Tcl_Command Gotest_CreateObjCommand(Tcl_Interp *interp, const char *cmdName,
		Tcl_ObjCmdProc *proc, void *clientData, Tcl_CmdDeleteProc *deleteProc) {
#if TCL_MAJOR_VERSION >= 9
	return Tcl_CreateObjCommand(interp, cmdName, proc, clientData, deleteProc);
#else
	return Tcl_CreateObjCommand(interp, cmdName, proc, (ClientData)clientData, deleteProc);
#endif
}

#endif
