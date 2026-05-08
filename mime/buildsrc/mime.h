#ifndef MIME_H
#define MIME_H

#include <tcl.h>
#include <stdlib.h>

/* Tcl 9 compatibility */
#ifndef TCL_SIZE_MAX
#  ifndef Tcl_Size
     typedef int Tcl_Size;
#  endif
#  define TCL_SIZE_MAX INT_MAX
#  define TCL_SIZE_MODIFIER ""
#endif

typedef Tcl_Obj *const *Tcl_ObjArgs;

DLLEXPORT int MimeTypeCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeExtensionsCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeAddCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeParseCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeFormatCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeEncodeCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeDecodeCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeDecodeHeaderCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);

/*
 * Wrapper for Tcl_CreateObjCommand to unify the ClientData type
 * difference between Tcl 8 (ClientData) and Tcl 9 (void *).
 */
static inline Tcl_Command Mime_CreateObjCommand(Tcl_Interp *interp, const char *cmdName,
		Tcl_ObjCmdProc *proc, void *clientData, Tcl_CmdDeleteProc *deleteProc) {
#if TCL_MAJOR_VERSION >= 9
	return Tcl_CreateObjCommand(interp, cmdName, proc, clientData, deleteProc);
#else
	return Tcl_CreateObjCommand(interp, cmdName, proc, (ClientData)clientData, deleteProc);
#endif
}

static inline void Mime_SetupNamespace(Tcl_Interp *interp) {
	Tcl_CreateNamespace(interp, "::mime2", NULL, NULL);
}

static inline void Mime_SetupEnsemble(Tcl_Interp *interp) {
	Tcl_Namespace *nsPtr = Tcl_FindNamespace(interp, "::mime2", NULL, 0);
	if (nsPtr != NULL) {
		Tcl_Export(interp, nsPtr, "*", 0);
		Tcl_CreateEnsemble(interp, "::mime", nsPtr, TCL_ENSEMBLE_PREFIX);
	}
}

#endif
