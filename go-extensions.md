# Go Extensions for KitCreator

This document describes KitCreator's Go integration architecture: how Go
owns the main entry point (gokit), and how Go-based Tcl extensions can be
statically linked into a Tclkit binary.

## Overview

When Go is available (`HAVE_GO=yes`), KitCreator builds the Tclkit using
`go build` instead of the traditional C linker. Go owns `main()`, and all
existing C object files (kitInit.o, Tcl libraries, extension archives) are
linked in via cgo's `CGO_LDFLAGS`.

This architecture also enables **Go-based Tcl extensions** to be statically
compiled into the same binary. Because everything shares a single Go runtime,
this avoids the multiple-GC problem that would occur with Go shared libraries.

## Go Entry Point (gokit)

The `kitsh/buildsrc/kitsh-0.0/gokit/` directory contains the Go `main`
package that replaces the traditional C `main.c`/`winMain.c` entry points.

### Source Files

| File | Purpose |
|------|---------|
| `main_unix.go` | Unix entry: builds `argc`/`argv` from `os.Args`, calls `Tcl_Main` via cgo |
| `main_windows.go` | Windows GUI entry (build tag `needwinmain`): calls `cgo_call_winmain()` |
| `main_windows_console.go` | Windows console entry (no `needwinmain` tag): same as Unix path |
| `cgo_helpers.c` | C shims: `cgo_call_tcl_main()`, `cgo_call_tk_main()` |
| `cgo_helpers_windows.c` | Windows `cgo_call_winmain()` adapted from `winMain.c` |
| `cgo_helpers.h` | Declarations for the C shims |
| `go.mod` | Module definition (`kitcreator/kitsh/gokit`), extended at configure time |

### Build Mechanism

The `Makefile.tclkit.in` build recipe for the `kit` target (when `HAVE_GO=yes`):

```makefile
cd $(CURDIR)/gokit && \
CGO_ENABLED=1 \
CC="$(CC)" \
CGO_CFLAGS="$(CPPFLAGS) $(CFLAGS)" \
CGO_LDFLAGS="<all .o files, .a archives, linker flags>" \
$(GO) build -o $(CURDIR)/kit <build tags> .
```

Key points:
- `CGO_CFLAGS` and `CGO_LDFLAGS` are set as environment variables (not
  `#cgo` directives), so they apply globally to all packages in the build.
- Build tags (e.g., `needwinmain`) are passed via `GO_BUILD_TAGS`, which is
  set during configure based on the target platform.
- When `HAVE_GO=no`, the build falls back to the traditional C linker using
  `main.c`/`winMain.c`.

### Platform Selection

| Platform | Build Tags | Entry |
|----------|------------|-------|
| Unix/macOS | (none) | `main_unix.go` -> `Tcl_Main` |
| Windows + Tk | `needwinmain` | `main_windows.go` -> `cgo_call_winmain` -> `Tk_Main` |
| Windows, no Tk | (none) | `main_windows_console.go` -> `Tcl_Main` |

## Go Extension Architecture

### How C Extensions Work (existing)

For reference, the existing C extension pipeline:

1. Each extension builds `.a` archive files into `<ext>/inst/lib/`
2. `DC_FIND_TCLKIT_LIBS` (in `aclocal.m4`) discovers them at configure time
3. It generates `kitInit-libs.h`, which defines `_Tclkit_GenericLib_Init()`
4. `kitInit.c` calls that function during `TclKit_AppInit`, which registers
   each extension via `Tcl_StaticPackage()`

### How Go Extensions Work

Go extensions follow an analogous pattern:

1. Each extension places a Go package in `<ext>/inst/go-pkg/`
2. `DC_FIND_GOKIT_LIBS` (in `aclocal.m4`) discovers them at configure time
3. It generates `gokit/kitInit-libs.go` with blank imports for each package
4. It appends `require`/`replace` blocks to `gokit/go.mod` so Go can resolve
   the local packages
5. Each extension's `init()` function registers itself by calling a C shim
   that invokes `Tcl_StaticPackage(NULL, ...)`

Because Go's `init()` functions run before `main()`, all extensions are
registered before `Tcl_Main` is called.

### Go Extension Package Layout

An extension named `myext` would provide:

```
myext/inst/go-pkg/
    go.mod         # module kitcreator/ext/myext
    register.go    # init() { C.goext_register_myext() }
    register.c     # void goext_register_myext() { Tcl_StaticPackage(NULL, "myext", Myext_Init, NULL); }
    myext.go       # Extension implementation (cgo)
    myext.c        # C helper code (optional)
```

**Module path convention:** `kitcreator/ext/<dirname>`

**Key rules:**
- No `#cgo CFLAGS:` or `#cgo LDFLAGS:` directives are needed. The Makefile
  sets `CGO_CFLAGS` and `CGO_LDFLAGS` as environment variables, which apply
  globally to all packages built by `go build`.
- `Tcl_StaticPackage(NULL, ...)` is safe to call before `Tcl_Main` -- it
  simply appends to a global list.

### Extension Types

An extension can be:

| Type | C archive (`inst/lib/*.a`) | Go package (`inst/go-pkg/`) | Notes |
|------|---|----|-------|
| **C-only** | Yes | No | Traditional path via `kitInit-libs.h` |
| **Go-only** | No | Yes | Registered via Go `init()` |
| **Hybrid** | Yes | Yes | Should register via one path only to avoid duplicates |

### Auto-Discovery (`DC_FIND_GOKIT_LIBS`)

The `DC_FIND_GOKIT_LIBS` macro in `aclocal.m4`:

1. Guards on `HAVE_GO=yes` (silently skipped otherwise)
2. Scans `../../../*/inst/go-pkg/` for directories containing `.go` files
3. For each discovered extension, accumulates:
   - A blank import line for `kitInit-libs.go`
   - A `require` entry for `go.mod`
   - A `replace` entry pointing to the local source path
4. Generates `gokit/kitInit-libs.go`
5. Appends `require`/`replace` blocks to `gokit/go.mod`

This macro is called at the end of `DC_FIND_TCLKIT_LIBS`, after C extension
discovery completes.

### Generated Files

**`gokit/kitInit-libs.go`** (with extensions):
```go
// Code generated by configure. DO NOT EDIT.

package main

import (
	_ "kitcreator/ext/myext"
	_ "kitcreator/ext/anotherext"
)
```

**`gokit/kitInit-libs.go`** (no extensions found):
```go
// Code generated by configure. DO NOT EDIT.

package main
```

**`gokit/go.mod`** (appended to the build copy):
```
module kitcreator/kitsh/gokit

go 1.21

require (
	kitcreator/ext/myext v0.0.0
	kitcreator/ext/anotherext v0.0.0
)

replace (
	kitcreator/ext/myext => ../../../../myext/inst/go-pkg
	kitcreator/ext/anotherext => ../../../../anotherext/inst/go-pkg
)
```

The `replace` paths are relative from the `gokit/` build directory up through
the build tree to the extension's source: `gokit/` -> `kitsh-0.0/` ->
`build/` -> `kitsh/` -> kitcreator root -> `<ext>/inst/go-pkg`.

## Writing a Go Extension

Here is a minimal example for an extension called `hello`:

**`hello/inst/go-pkg/go.mod`:**
```
module kitcreator/ext/hello

go 1.21
```

**`hello/inst/go-pkg/register.go`:**
```go
package hello

/*
#include "register.h"
*/
import "C"

func init() {
	C.goext_register_hello()
}
```

**`hello/inst/go-pkg/register.h`:**
```c
void goext_register_hello(void);
```

**`hello/inst/go-pkg/register.c`:**
```c
#include <tcl.h>
#include "register.h"

extern int Hello_Init(Tcl_Interp *interp);

void goext_register_hello(void) {
    Tcl_StaticPackage(NULL, "hello", Hello_Init, NULL);
}
```

**`hello/inst/go-pkg/hello.go`:**
```go
package hello

/*
#include <tcl.h>
#include <string.h>

static int HelloCmd(ClientData clientData, Tcl_Interp *interp,
    int objc, Tcl_Obj *const objv[]) {
    Tcl_SetObjResult(interp, Tcl_NewStringObj("Hello from Go!", -1));
    return TCL_OK;
}

int Hello_Init(Tcl_Interp *interp) {
    Tcl_CreateObjCommand(interp, "hello", HelloCmd, NULL, NULL);
    if (Tcl_PkgProvide(interp, "hello", "1.0") != TCL_OK) {
        return TCL_ERROR;
    }
    return TCL_OK;
}
*/
import "C"
```

After building, the extension is available in Tcl:
```tcl
package require hello
hello   ;# => "Hello from Go!"
```

## Build Behavior

| Scenario | Result |
|----------|--------|
| No Go extensions present | `kitInit-libs.go` generated with just `package main`; `go.mod` unchanged |
| Go extensions present | Blank imports and `go.mod` entries generated; extensions linked into binary |
| `HAVE_GO=no` (or Go unavailable) | `DC_FIND_GOKIT_LIBS` is skipped entirely; C fallback build used |
