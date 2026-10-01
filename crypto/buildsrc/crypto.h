#ifndef CRYPTO_H
#define CRYPTO_H

#include "tclcgo.h"
#include <stdlib.h>

DLLEXPORT int CryptoHashCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int CryptoHmacCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);

#endif
