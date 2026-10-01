#ifndef TCLCGO_H
#define TCLCGO_H

/*
 * Shared cgo glue for Go extensions.
 *
 * cgo cannot call C macros or express const pointer types, and some Tcl
 * API entry points are macros or differ in type between Tcl versions.
 * Each wrapper here is named cgo_<Tcl function> and simply calls the Tcl
 * function, letting the C preprocessor resolve any macro.
 *
 * Only add a wrapper when no real function exists across all supported
 * Tcl versions; otherwise call the real function directly from Go
 * (e.g., Tcl_GetStringFromObj(obj, nil) instead of Tcl_GetString).
 */

#include <tcl.h>

#ifndef TCL_SIZE_MAX
#  ifndef Tcl_Size
     typedef int Tcl_Size;
#  endif
#  define TCL_SIZE_MAX INT_MAX
#  define TCL_SIZE_MODIFIER ""
#endif

typedef Tcl_Obj *const *Tcl_ObjArgs;

static inline int cgo_Tcl_Close(Tcl_Interp *interp, Tcl_Channel chan) {
	return Tcl_Close(interp, chan);
}

static inline unsigned char *cgo_Tcl_GetByteArrayFromObj(Tcl_Obj *objPtr, Tcl_Size *sizePtr) {
	return Tcl_GetByteArrayFromObj(objPtr, sizePtr);
}

static inline Tcl_Command cgo_Tcl_CreateObjCommand(Tcl_Interp *interp, const char *cmdName,
		Tcl_ObjCmdProc *proc, void *clientData, Tcl_CmdDeleteProc *deleteProc) {
	return Tcl_CreateObjCommand(interp, cmdName, proc, clientData, deleteProc);
}

#endif
