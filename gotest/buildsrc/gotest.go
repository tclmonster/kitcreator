package gotest

/*
#include "gotest.h"
*/
import "C"
import (
	"fmt"
	"runtime"
	"unsafe"
)

//export Gotest_Init
func Gotest_Init(interp *C.Tcl_Interp) C.int {
	C.Tcl_CreateObjCommand(interp, C.CString("gotest::hello"), (*C.Tcl_ObjCmdProc)(C.GotestHelloObjCmd), nil, nil)
	return C.Tcl_PkgProvide(interp, C.CString("gotest"), C.CString("1.0"))
}

//export GotestHelloObjCmd
func GotestHelloObjCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	msg := fmt.Sprintf("Hello from Go %s!", runtime.Version())
	cMsg := C.CString(msg)
	defer C.free(unsafe.Pointer(cMsg))
	C.Tcl_SetObjResult(interp, C.Tcl_NewStringObj(cMsg, C.int(-1)))
	return C.TCL_OK
}
