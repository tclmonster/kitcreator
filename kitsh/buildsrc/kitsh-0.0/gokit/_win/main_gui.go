//go:build windows && needwinmain

package main

/*
#include "cgo_helpers.h"
*/
import "C"

func main() {
	useUTF8Console()
	C.cgo_call_winmain()
}
