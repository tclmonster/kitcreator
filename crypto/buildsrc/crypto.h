#ifndef CRYPTO_H
#define CRYPTO_H

#include "tclcgo.h"
#include <stdlib.h>

DLLEXPORT int CryptoHashCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);
DLLEXPORT int CryptoHmacCmd(ClientData, Tcl_Interp *, int, Tcl_ObjArgs);

/*
 * The bytes to hash: Tcl_GetBytesFromObj on 9. On 8.6, which lacks it, refuse
 * code points above 0xFF as 9 does rather than let Tcl_GetByteArrayFromObj
 * truncate them.
 */
static inline unsigned char *CryptoGetBytesFromObj(Tcl_Interp *interp, Tcl_Obj *objPtr,
		Tcl_Size *sizePtr) {
#if TCL_MAJOR_VERSION > 8
	return Tcl_GetBytesFromObj(interp, objPtr, sizePtr);
#else
	int len, offset = 0;
	const char *s = Tcl_GetStringFromObj(objPtr, &len), *end = s + len;
	while (s < end) {
		Tcl_UniChar ch = 0;
		s += Tcl_UtfToUniChar(s, &ch);
		if (ch > 0xFF) {
			if (interp != NULL) {
				Tcl_SetObjResult(interp, Tcl_ObjPrintf(
					"expected code point values below 0xff but value at byte offset %d was 0x%x",
					offset, (int)ch));
				Tcl_SetErrorCode(interp, "TCL", "VALUE", "BYTES", (char *)NULL);
			}
			return NULL;
		}
		offset++;
	}
	return Tcl_GetByteArrayFromObj(objPtr, sizePtr);
#endif
}

#endif
