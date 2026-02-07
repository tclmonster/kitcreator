package main

/*
#include <tcl.h>
#include <tk.h>

static int Cgo_Tcl_AppInit(Tcl_Interp *interp) {
    if (Tcl_Init(interp) == TCL_ERROR) {
        return TCL_ERROR;
    }
    if (Tk_Init(interp) == TCL_ERROR) {
        return TCL_ERROR;
    }
#ifdef _WIN32
    if (Tk_CreateConsoleWindow(interp) == TCL_ERROR) {
        return TCL_ERROR;
    }
#endif
    return TCL_OK;
}

static void cgo_call_tk_main(int argc, char **argv) {
    Tk_Main(argc, argv, Cgo_Tcl_AppInit);
}
*/
import "C"
import (
	"os"
	"unsafe"
)

func main() {
	argc := C.int(len(os.Args))
	argv := make([]*C.char, len(os.Args)+1)
	for i, arg := range os.Args {
		argv[i] = C.CString(arg)
	}
	argv[len(os.Args)] = nil
	C.cgo_call_tk_main(argc, (**C.char)(unsafe.Pointer(&argv[0])))
	os.Exit(1) // Tk_Main should not return
}
