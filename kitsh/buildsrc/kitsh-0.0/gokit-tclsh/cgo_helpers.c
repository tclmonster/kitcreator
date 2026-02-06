#include <tcl.h>

static int Cgo_Tcl_AppInit(Tcl_Interp *interp) {
    return Tcl_Init(interp);
}

void cgo_call_tcl_main(int argc, char **argv) {
    Tcl_Main(argc, argv, Cgo_Tcl_AppInit);
}
