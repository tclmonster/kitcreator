#ifndef GOTEST_H
#define GOTEST_H

#include <tcl.h>
#include <stdlib.h>

typedef Tcl_Obj *const *Tcl_ObjArgs;

extern int GotestHelloObjCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);

#endif
