//go:build windows

package main

import "golang.org/x/sys/windows"

const codePageUTF8 = 65001

// useUTF8Console makes the console decode what C and Go code write as UTF-8
// (a progress bar's box-drawing characters, a log line) instead of using the
// OEM code page. Tcl's console channel writes UTF-16 and is unaffected. Both
// calls fail harmlessly when the process has no console.
func useUTF8Console() {
	windows.SetConsoleOutputCP(codePageUTF8)
	windows.SetConsoleCP(codePageUTF8)
}
