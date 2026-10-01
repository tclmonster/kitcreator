#ifndef MIME_H
#define MIME_H

#include "tclcgo.h"
#include <stdlib.h>

DLLEXPORT int MimeTypeCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeExtensionsCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeAddCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeParseCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeFormatCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeEncodeCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeDecodeCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int MimeDecodeHeaderCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);

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
