package mime

/*
#include "mime.h"
*/
import "C"
import (
	gomime "mime"
	"unsafe"
)

func getArgs(objv C.Tcl_ObjArgs, objc C.int) []*C.Tcl_Obj {
	return unsafe.Slice((**C.Tcl_Obj)(unsafe.Pointer(objv)), int(objc))
}

func getString(obj *C.Tcl_Obj) string {
	return C.GoString(C.Tcl_GetString(obj))
}

func setError(interp *C.Tcl_Interp, msg string) C.int {
	cMsg := C.CString(msg)
	defer C.free(unsafe.Pointer(cMsg))
	C.Tcl_SetObjResult(interp, C.Tcl_NewStringObj(cMsg, C.Tcl_Size(-1)))
	return C.TCL_ERROR
}

func setStringResult(interp *C.Tcl_Interp, s string) {
	cs := C.CString(s)
	defer C.free(unsafe.Pointer(cs))
	C.Tcl_SetObjResult(interp, C.Tcl_NewStringObj(cs, C.Tcl_Size(-1)))
}

func newStringObj(s string) *C.Tcl_Obj {
	cs := C.CString(s)
	defer C.free(unsafe.Pointer(cs))
	return C.Tcl_NewStringObj(cs, C.Tcl_Size(-1))
}

func dictPut(interp *C.Tcl_Interp, dict *C.Tcl_Obj, key, value string) {
	C.Tcl_DictObjPut(interp, dict, newStringObj(key), newStringObj(value))
}

//export Mime_Init
func Mime_Init(interp *C.Tcl_Interp) C.int {
	C.Mime_SetupNamespace(interp)

	C.Mime_CreateObjCommand(interp, C.CString("::mime::type"), (*C.Tcl_ObjCmdProc)(C.MimeTypeCmd), nil, nil)
	C.Mime_CreateObjCommand(interp, C.CString("::mime::extensions"), (*C.Tcl_ObjCmdProc)(C.MimeExtensionsCmd), nil, nil)
	C.Mime_CreateObjCommand(interp, C.CString("::mime::add"), (*C.Tcl_ObjCmdProc)(C.MimeAddCmd), nil, nil)
	C.Mime_CreateObjCommand(interp, C.CString("::mime::parse"), (*C.Tcl_ObjCmdProc)(C.MimeParseCmd), nil, nil)
	C.Mime_CreateObjCommand(interp, C.CString("::mime::format"), (*C.Tcl_ObjCmdProc)(C.MimeFormatCmd), nil, nil)
	C.Mime_CreateObjCommand(interp, C.CString("::mime::encode"), (*C.Tcl_ObjCmdProc)(C.MimeEncodeCmd), nil, nil)
	C.Mime_CreateObjCommand(interp, C.CString("::mime::decode"), (*C.Tcl_ObjCmdProc)(C.MimeDecodeCmd), nil, nil)
	C.Mime_CreateObjCommand(interp, C.CString("::mime::decodeheader"), (*C.Tcl_ObjCmdProc)(C.MimeDecodeHeaderCmd), nil, nil)

	C.Mime_SetupEnsemble(interp)

	return C.Tcl_PkgProvideEx(interp, C.CString("mime"), C.CString("1.0"), nil)
}

//export MimeTypeCmd
func MimeTypeCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	if int(objc) != 2 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" extension\"")
	}
	ext := getString(args[1])
	result := gomime.TypeByExtension(ext)
	setStringResult(interp, result)
	return C.TCL_OK
}

//export MimeExtensionsCmd
func MimeExtensionsCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	if int(objc) != 2 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" type\"")
	}
	typ := getString(args[1])
	exts, err := gomime.ExtensionsByType(typ)
	if err != nil {
		return setError(interp, err.Error())
	}
	list := C.Tcl_NewListObj(C.Tcl_Size(0), nil)
	for _, e := range exts {
		C.Tcl_ListObjAppendElement(interp, list, newStringObj(e))
	}
	C.Tcl_SetObjResult(interp, list)
	return C.TCL_OK
}

//export MimeAddCmd
func MimeAddCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	if int(objc) != 3 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" extension type\"")
	}
	ext := getString(args[1])
	typ := getString(args[2])
	if err := gomime.AddExtensionType(ext, typ); err != nil {
		return setError(interp, err.Error())
	}
	return C.TCL_OK
}

//export MimeParseCmd
func MimeParseCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	if int(objc) != 2 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" value\"")
	}
	v := getString(args[1])
	mediatype, params, err := gomime.ParseMediaType(v)
	if err != nil {
		return setError(interp, err.Error())
	}
	dict := C.Tcl_NewDictObj()
	dictPut(interp, dict, "mediatype", mediatype)
	for k, val := range params {
		dictPut(interp, dict, k, val)
	}
	C.Tcl_SetObjResult(interp, dict)
	return C.TCL_OK
}

//export MimeFormatCmd
func MimeFormatCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	n := int(objc)
	if n < 2 || (n-2)%2 != 0 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" type ?key value ...?\"")
	}
	t := getString(args[1])
	params := make(map[string]string)
	for i := 2; i < n; i += 2 {
		params[getString(args[i])] = getString(args[i+1])
	}
	result := gomime.FormatMediaType(t, params)
	setStringResult(interp, result)
	return C.TCL_OK
}

//export MimeEncodeCmd
func MimeEncodeCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	n := int(objc)
	if n < 3 || n > 4 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" ?-q? charset string\"")
	}
	var encoder gomime.WordEncoder = gomime.BEncoding
	argIdx := 1
	if n == 4 {
		flag := getString(args[1])
		if flag != "-q" {
			return setError(interp, "bad option \""+flag+"\": must be -q")
		}
		encoder = gomime.QEncoding
		argIdx = 2
	}
	charset := getString(args[argIdx])
	s := getString(args[argIdx+1])
	result := encoder.Encode(charset, s)
	setStringResult(interp, result)
	return C.TCL_OK
}

//export MimeDecodeCmd
func MimeDecodeCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	if int(objc) != 2 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" word\"")
	}
	word := getString(args[1])
	var d gomime.WordDecoder
	result, err := d.Decode(word)
	if err != nil {
		return setError(interp, err.Error())
	}
	setStringResult(interp, result)
	return C.TCL_OK
}

//export MimeDecodeHeaderCmd
func MimeDecodeHeaderCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	args := getArgs(objv, objc)
	if int(objc) != 2 {
		return setError(interp, "wrong # args: should be \""+getString(args[0])+" string\"")
	}
	header := getString(args[1])
	var d gomime.WordDecoder
	result, err := d.DecodeHeader(header)
	if err != nil {
		return setError(interp, err.Error())
	}
	setStringResult(interp, result)
	return C.TCL_OK
}
