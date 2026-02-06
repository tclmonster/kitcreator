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

void cgo_call_tk_main(int argc, char **argv) {
    Tk_Main(argc, argv, Cgo_Tcl_AppInit);
}
