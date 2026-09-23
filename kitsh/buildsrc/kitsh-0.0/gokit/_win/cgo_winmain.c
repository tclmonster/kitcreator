#ifdef _WIN32
#ifndef TCLKIT_DLL
/*
 * cgo_winmain.c --
 *
 *	C shim for the Go GUI entry point (_win/main_gui.go).
 *	Includes winMain.c for shared code (WinMain, setargv, etc.),
 *	then provides cgo_call_winmain() as the Go-callable entry.
 */

#ifdef KITSH_NEED_WINMAIN
#include "../winMain.c"

void cgo_call_winmain(void)
{
    WinMain(GetModuleHandle(NULL), NULL, GetCommandLine(), SW_SHOWNORMAL);
}
#else
void cgo_call_winmain(void) {}
#endif

#else
/* Stub for KitDLL c-shared build -- never called. */
void cgo_call_winmain(void) {}
#endif /* !TCLKIT_DLL */
#endif /* _WIN32 */
