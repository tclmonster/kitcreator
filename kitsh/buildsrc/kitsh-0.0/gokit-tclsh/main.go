package main

/*
#include <tcl.h>

static int Cgo_Tcl_AppInit(Tcl_Interp *interp) {
    return Tcl_Init(interp);
}

static void cgo_call_tcl_main(int argc, char **argv) {
    Tcl_Main(argc, argv, Cgo_Tcl_AppInit);
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
	C.cgo_call_tcl_main(argc, (**C.char)(unsafe.Pointer(&argv[0])))
	os.Exit(1) // Tcl_Main should not return
}
