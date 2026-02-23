#ifndef CRYPTO_H
#define CRYPTO_H

#include <tcl.h>
#include <stdlib.h>

typedef Tcl_Obj *const *Tcl_ObjArgs;

DLLEXPORT int CryptoHashCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int CryptoHmacCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);

#endif
