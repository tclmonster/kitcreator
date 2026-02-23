package crypto

/*
#include "crypto.h"
*/
import "C"
import (
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"hash"
	"unsafe"
)

const (
	algoMD5 = iota
	algoSHA1
	algoSHA224
	algoSHA256
	algoSHA384
	algoSHA512
)

func newHash(algo int) hash.Hash {
	switch algo {
	case algoMD5:
		return md5.New()
	case algoSHA1:
		return sha1.New()
	case algoSHA224:
		return sha256.New224()
	case algoSHA256:
		return sha256.New()
	case algoSHA384:
		return sha512.New384()
	case algoSHA512:
		return sha512.New()
	}
	return nil
}

var algoNames = map[string]int{
	"md5":    algoMD5,
	"sha1":   algoSHA1,
	"sha224": algoSHA224,
	"sha256": algoSHA256,
	"sha384": algoSHA384,
	"sha512": algoSHA512,
}

func tclError(interp *C.Tcl_Interp, msg string) C.int {
	cMsg := C.CString(msg)
	defer C.free(unsafe.Pointer(cMsg))
	C.Tcl_SetObjResult(interp, C.Tcl_NewStringObj(cMsg, C.int(-1)))
	return C.TCL_ERROR
}

func tclOk(interp *C.Tcl_Interp, result string) C.int {
	cResult := C.CString(result)
	defer C.free(unsafe.Pointer(cResult))
	C.Tcl_SetObjResult(interp, C.Tcl_NewStringObj(cResult, C.int(-1)))
	return C.TCL_OK
}

func hashBytes(h hash.Hash, data []byte) string {
	h.Write(data)
	return hex.EncodeToString(h.Sum(nil))
}

func hashChannel(h hash.Hash, interp *C.Tcl_Interp, channel C.Tcl_Channel) (string, bool) {
	var buf [4096]C.char
	for {
		n := C.Tcl_Read(channel, &buf[0], C.int(len(buf)))
		if n < 0 {
			return "", false
		}
		if n == 0 {
			break
		}
		h.Write(C.GoBytes(unsafe.Pointer(&buf[0]), n))
	}
	return hex.EncodeToString(h.Sum(nil)), true
}

func hashFile(h hash.Hash, interp *C.Tcl_Interp, filename *C.char) (string, bool) {
	channel := C.Tcl_OpenFileChannel(interp, filename, C.CString("r"), 0)
	if channel == nil {
		return "", false
	}
	C.Tcl_SetChannelOption(interp, channel, C.CString("-translation"), C.CString("binary"))

	result, ok := hashChannel(h, interp, channel)
	C.Tcl_Close(interp, channel)
	return result, ok
}

// computeHash handles the three input modes: data, -channel, -file
// objv[0] is the command name; remaining args start at offset.
func computeHash(h hash.Hash, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs, offset int) C.int {
	argc := int(objc) - offset
	args := unsafe.Slice(objv, int(objc))

	if argc == 1 {
		// Positional data
		var dataLen C.int
		dataPtr := C.Tcl_GetByteArrayFromObj(args[offset], &dataLen)
		data := C.GoBytes(unsafe.Pointer(dataPtr), dataLen)
		return tclOk(interp, hashBytes(h, data))
	}

	if argc == 2 {
		flag := C.GoString(C.Tcl_GetString(args[offset]))
		switch flag {
		case "-channel":
			var mode C.int
			cChanName := C.Tcl_GetString(args[offset+1])
			channel := C.Tcl_GetChannel(interp, cChanName, &mode)
			if channel == nil {
				return C.TCL_ERROR
			}
			result, ok := hashChannel(h, interp, channel)
			if !ok {
				return tclError(interp, "error reading channel")
			}
			return tclOk(interp, result)

		case "-file":
			cFilename := C.Tcl_GetString(args[offset+1])
			result, ok := hashFile(h, interp, cFilename)
			if !ok {
				return C.TCL_ERROR // error already set by Tcl_OpenFileChannel
			}
			return tclOk(interp, result)
		}
	}

	return tclError(interp, "wrong # args: should be \"command data\" or \"command -channel chan\" or \"command -file path\"")
}

//export Crypto_Init
func Crypto_Init(interp *C.Tcl_Interp) C.int {
	cmds := []struct {
		name string
		algo int
	}{
		{"crypto::md5", algoMD5},
		{"crypto::sha1", algoSHA1},
		{"crypto::sha224", algoSHA224},
		{"crypto::sha256", algoSHA256},
		{"crypto::sha384", algoSHA384},
		{"crypto::sha512", algoSHA512},
	}
	for _, cmd := range cmds {
		cName := C.CString(cmd.name)
		C.Tcl_CreateObjCommand(interp, cName, (*C.Tcl_ObjCmdProc)(C.CryptoHashCmd), C.ClientData(unsafe.Pointer(uintptr(cmd.algo))), nil)
	}

	cHmacName := C.CString("crypto::hmac")
	C.Tcl_CreateObjCommand(interp, cHmacName, (*C.Tcl_ObjCmdProc)(C.CryptoHmacCmd), nil, nil)

	return C.Tcl_PkgProvide(interp, C.CString("crypto"), C.CString("1.0"))
}

//export CryptoHashCmd
func CryptoHashCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	algo := int(uintptr(unsafe.Pointer(clientData)))
	h := newHash(algo)
	if h == nil {
		return tclError(interp, "unknown hash algorithm")
	}
	// args after command name start at index 1
	return computeHash(h, interp, objc, objv, 1)
}

//export CryptoHmacCmd
func CryptoHmacCmd(clientData C.ClientData, interp *C.Tcl_Interp, objc C.int, objv C.Tcl_ObjArgs) C.int {
	// crypto::hmac <algorithm> <key> <data|-channel chan|-file path>
	if int(objc) < 4 {
		return tclError(interp, "wrong # args: should be \"crypto::hmac algorithm key data\" or \"crypto::hmac algorithm key -channel chan\" or \"crypto::hmac algorithm key -file path\"")
	}

	args := unsafe.Slice(objv, int(objc))

	algoName := C.GoString(C.Tcl_GetString(args[1]))
	algo, ok := algoNames[algoName]
	if !ok {
		return tclError(interp, "unknown algorithm \""+algoName+"\": must be md5, sha1, sha224, sha256, sha384, or sha512")
	}

	var keyLen C.int
	keyPtr := C.Tcl_GetByteArrayFromObj(args[2], &keyLen)
	key := C.GoBytes(unsafe.Pointer(keyPtr), keyLen)

	h := hmac.New(func() hash.Hash { return newHash(algo) }, key)

	// Remaining args start at index 3
	return computeHash(h, interp, objc, objv, 3)
}

func main() {}
