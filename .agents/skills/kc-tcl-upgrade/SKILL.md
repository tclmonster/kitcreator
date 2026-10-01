---
name: kc-tcl-upgrade
description: Upgrade or add a Tcl/Tk release in KitCreator (e.g. 9.0.3 to 9.0.4, or adding 9.1), find upstream changes that break the kit or its packages, and smoke-test the resulting Tclkit. Use when the user asks to upgrade, add or test a Tcl/Tk version, or when a kit misbehaves after one.
---

# Upgrading Tcl/Tk

## 1. Version and hashes

For release `X.Y.Z` (the user usually supplies SHA256s of `tclX.Y.Z-src.tar.gz`
and `tkX.Y.Z-src.tar.gz`; the build verifies them on download):

- `kitcreator`: default `TCLVERS`.
- `tcl/build.sh`, `tk/build.sh`: an `X.Y.Z)` case with `SRCHASH`.
- `build/web/kitcreator.vfs/index.rvt`: `tcl_versions(X.Y.Z)`.
- `build/test/test`: `VERSIONS`.
- `.github/workflows/build-{linux,macos,windows}.yml`: the `tcl_tk_version`
  matrix; `create-release.yml`: the Linux kit that runs the release script.

Ask whether the new version replaces the old one in CI or is added alongside.

## 2. Upstream changes that affect KitCreator

Diff the old and new source releases (`tcl/src/`, `tk/src/`, or download the
old one). Most breakage this has caught came from:

- `generic/tclDecls.h`, `tcl.h`: functions that became macro-only (cgo cannot
  call them; see `docs/go-extensions.md`), fields hidden under
  `TCL_NO_DEPRECATED` (packages that define it, e.g. cffi), and struct changes.
- `generic/tclCompile.h`, `tclInt.h`: opcodes and internal structs used by
  tbcload/tclcompiler.
- `unix/Makefile.in`, `win/Makefile.in`: installed headers and libraries
  (9.0.4 stopped installing `tommath.h` on Windows).
- `generic/tclInterp.c` (`Tcl_Init`): how `init.tcl` is found. The kit's
  startup (`kitsh/buildsrc/kitsh-0.0/boot.tcl`, `kitInit.c`) depends on it;
  9.1 stopped calling `tclInit`.

Then check the Tcl, Tk and package patches still apply (`kc-patches`).

## 3. Build

Build each Tcl version CI builds with the matching package list
(`.github/workflows/pkgs-gui.txt` for 8.6, `pkgs-gui-tcl9.txt` for 9.x) and the
workflow's `env:` and options. Every package must report `done`; read
`<pkg>/build.log` for failures. Windows and macOS only build in CI.

## 4. Smoke test

```sh
.agents/skills/kc-tcl-upgrade/scripts/smoke-test-kit [-t] <kit> <package>...
```

Runs a copy of the kit outside the repository and checks that `tcl_library`
and `auto_path` are inside the kit and that each package loads, in the main
and a child interpreter. `-t` also round-trips a proc through tclcompiler and
tbcload. Use the Tcl package names (`Tclx`, `md5`), not directory names; Tk
packages need a display.

A kit whose `tcl_library` points at `tcl/inst/lib` is not starting from its
own VFS: check the startup code against upstream `Tcl_Init`.
