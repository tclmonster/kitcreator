#include "config.h"
#include <tcl.h>

extern int TclKit_AppInit(Tcl_Interp *interp);

void cgo_call_tcl_main(int argc, char **argv) {
    Tcl_Main(argc, argv, TclKit_AppInit);
}

#ifdef KIT_INCLUDES_TK
#include <tk.h>
void cgo_call_tk_main(int argc, char **argv) {
    Tk_Main(argc, argv, TclKit_AppInit);
}
#else
void cgo_call_tk_main(int argc, char **argv) {
    Tcl_Main(argc, argv, TclKit_AppInit);
}
#endif
