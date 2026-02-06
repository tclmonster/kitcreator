#ifndef CGO_HELPERS_H
#define CGO_HELPERS_H
void cgo_call_tcl_main(int argc, char **argv);
void cgo_call_tk_main(int argc, char **argv);
#ifdef _WIN32
void cgo_call_winmain(void);
#endif
#endif
