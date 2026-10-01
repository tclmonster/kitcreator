---
name: kc-patches
description: Add, refresh, regenerate, move or retire KitCreator source patches (<pkg>/patches/*.diff), including whole patch stacks. Use when a build reports "Patch does not apply" or "applied with fuzz", when upgrading Tcl/Tk or a package version, or when a patched change has landed upstream.
---

# KitCreator patches

Build scripts apply patches with `common/helpers/apply-patch` (`-p1`): a patch
that does not apply cleanly fails the build without touching the source;
fuzz is allowed but reported on the console. Details are in `<pkg>/build.log`.

## Which patches apply

In this order; alphabetical within a glob (use `000-` prefixes when order
matters); version-prefix directories least specific first (`9/`, `9.0/`).

| Package | Patches | Version |
|---|---|---|
| Tcl | `all/tcl-<ver>-*`, `all/tcl-all-*`, `<ver>/tcl-<ver>-*`, then all of each prefix dir | full (`9.0.4`) |
| Tk | `all/tk-<tkver>-*`, `<tclver>/tk-<tkver>-*` | major.minor |
| Common build system | `all/<pkg>-<version>-*`, `<tclver>/<pkg>-<version>-*`, `patches/*`, then all of each prefix dir of `<tclver>` | `<tclver>` major.minor |

A common-build-system patch is skipped if an executable `<patch>.sh` next to
it exits non-zero (`<patch>.sh <tclver> <pkg> <version>`).

## Format

`diff -ruN A/<file> B/<file>` without timestamps, with an optional
explanation above the first file section. Never hand-edit hunks (editors drop
the space on blank context lines, causing fuzz); regenerate instead.

## Regenerating: scripts/refresh-patches

```sh
.agents/skills/kc-patches/scripts/refresh-patches [-w <workdir>] <source> <patch>...
.agents/skills/kc-patches/scripts/refresh-patches --continue <workdir>
```

`<source>` is the pristine archive (`<pkg>/src/<pkg>-<version>.*`,
`tcl/src/tcl<ver>.tar.gz`, `tk/src/tk<ver>.tar.gz`) or a `buildsrc/`
directory. Pass the whole stack in build order: each patch is regenerated
against the ones before it. If one does not apply, finish the change in
`<workdir>/B` using the `.rej` files, delete them, and `--continue`.

After a refresh with no manual changes, `fossil diff` should show only
headers, context and line numbers changed, not `+`/`-` lines.

## Scenarios

- **Fuzz:** refresh the package's stack.
- **Does not apply** (often after an upgrade): if upstream now has the change,
  see below; otherwise refresh against the new source and port the change by
  hand when it stops. If older versions still need the old patch, place the
  new one so only the new version selects it.
- **Landed upstream:** `fossil mv` it to a prefix directory that only older
  versions select (e.g. `patches/9/` to `patches/9.0/`), or `fossil rm` it.
- **Irrelevant hunks:** Windows builds always use MSYS2/MinGW, so delete MSVC
  file sections (`win/makefile.vc`...), then refresh to verify.
- **New patch:** `refresh-patches -w <dir>` the existing stack (or extract the
  source into `<dir>/B`), copy `B` to `A`, edit `B`, then
  `diff -ruN A B` with timestamps stripped from `---`/`+++` lines.

## Verifying

`rm -f <pkg>/.success`, then `./kitcreator retry` with the package: the
console must show no patch `ERROR`/`WARNING`. For Tcl/Tk, build every Tcl
version the patch applies to.
