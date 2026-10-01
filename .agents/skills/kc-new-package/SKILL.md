---
name: kc-new-package
description: Add a new package to KitCreator - a C extension (TEA/autoconf) using the common build system, a pure Tcl package, or a Go extension - so it is built, statically linked and loadable with package require from the kit. Use when the user wants to add, port or package an extension.
---

# Adding a package

A package is a directory `<pkg>/` with an executable `build.sh`. Static
libraries in `<pkg>/inst/` are linked into the kit; `<pkg>/out/` is copied
into its VFS.

## C extension (common build system)

```sh
#! /usr/bin/env bash

# BuildCompatible: KitCreator

version='1.2.3'
url="https://example.org/foo-${version}.tar.gz"
sha256='...'
```

The marker line selects `common/common.sh`: download, extract, patch, a static
`configure` against the kit's Tcl, `make install` into `inst/`, then `inst/lib`
copied to `out/`. Override a step by defining its function (`configure`,
`install`, `postinstall`...); read `common/common.sh` first.

| Setting | When | Example |
|---|---|---|
| `configure_extra=(...)`, `make_extra=(...)` | extra arguments | `twapi` |
| `tclpkg`, `tclpkgversion` | Tcl package name/version differ from `<pkg>`/`version` | `tclx` |
| `tclpkg_initfunc` | init function is not `<Pkg>_Init` | `duktape` |
| `pkg_always_static`, `pkg_no_support_for_static` | force static / no static build | `tclvfs`, `tcllux` |
| `KC_<PKG>_CFLAGS` (`_LDFLAGS`, `_LIBS`...) | package-specific flags | `tclcompiler` |

kitsh links every `inst/**/*.a` and registers `<Pkg>_Init` as static package
`<Pkg>`; `createruntime` writes the matching `pkgIndex.tcl`. Extra link
libraries go in `<lib>.a.linkadd`, written in `postinstall` (see `cffi`);
`inst/kitcreator-nolibs` excludes libraries by regex (see `tcc4tcl`).

## Pure Tcl package

Install the files and their `pkgIndex.tcl` under `inst/lib/<pkg>` (see `tcllib`).

## Go extension

Built only with `--with-go`; see `docs/go-extensions.md`. Modelled on `crypto/`:

- `buildsrc/`: `<pkg>.go` with `//export <Pkg>_Init`, `<pkg>.h` including
  `tclcgo.h`, `go.mod` (`module kitcreator/ext/<pkg>`), and `pkgIndex.tcl`
  (`load {} <Pkg>`).
- `build.sh` (no marker) copies the `.go`, `.h` and `go.mod` files to
  `inst/go-pkg/` and `pkgIndex.tcl` to `out/lib/<pkg>/`.

## Finishing

- CI: add it to `.github/workflows/pkgs-*.txt`, and `STATIC<PKG>: 1` to the
  workflows' `env:` to build it statically there.
- `fossil add` the package, without `src/`, `build/`, `inst/` or `out/`.
- Verify: `KITCREATOR_PKGS='<pkg>' ./kitcreator build`, then
  `smoke-test-kit <kit> <tcl-package-name>` (`kc-tcl-upgrade`).
