#include <tcl.h>

#ifndef TCLKIT_DLL
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
#else
/* Stubs for KitDLL c-shared build -- never called. */
void cgo_call_tcl_main(int argc, char **argv) { (void)argc; (void)argv; }
void cgo_call_tk_main(int argc, char **argv) { (void)argc; (void)argv; }
#endif
