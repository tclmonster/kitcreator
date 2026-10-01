# AGENTS.md

KitCreator builds Tclkits and KitDLLs from Tcl, Tk, extension packages and the
`kitsh` glue layer. See `README` for usage.

Keep this file short: project-specific facts and preferences only, not what
the code or `README` already shows. Task-specific detail belongs in a skill.

## Working with the user

- Present findings and the intended approach before non-trivial edits.
- Do not commit until the user has reviewed and asks for it.

## Fossil

This repository uses Fossil, not git.

- Short commit messages; no `Co-Authored-By` or other attribution.
- Branch only when asked: `fossil commit --branch <name> -m "..."`.
- New files need `fossil add` (`--dotfiles` for paths starting with `.`).

## Building

- Code and patches must work on every Tcl version in the CI matrix
  (`tcl_tk_version` in `.github/workflows/build-*.yml`); use
  `TCL_MAJOR_VERSION`/`TCL_MINOR_VERSION` guards where they differ.
- `./kitcreator retry` skips packages that have a `<pkg>/.success` marker;
  delete it to rebuild one package. Changing the Tcl version needs `build`.
- Package output goes to `<pkg>/build.log`; only fd 4 reaches the console.
- A running `./tclkit-<version>` cannot be replaced, and the build does not
  say so; close it before rebuilding.
- Test kits from a copy outside the repository, so they cannot fall back to
  `tcl/inst/lib`.
- After editing `kitsh/buildsrc/kitsh-0.0/aclocal.m4`, run `build/pre.sh`.
  Never edit the generated `configure`.
- To reproduce CI, use the workflow's `env:`, `./kitcreator` options, and
  package list (`.github/workflows/pkgs-*.txt`).

## Packages

- Package-specific flags: `KC_<PKG>_CFLAGS` (etc.) in `<pkg>/build.sh`.
- To refuse an unsupported Tcl version, add a `predownload` hook to that
  package's `build.sh`, not a check in `./kitcreator`.
- Extensions are linked statically and registered with `Tcl_StaticPackage`;
  `pkgIndex.tcl` loads them with `load {} <Prefix>`, and the prefix must match
  the registered name exactly (`Gotest`, not `gotest`).
- Go extensions are optional (`--with-go`); see `docs/go-extensions.md`.

## Style

- Match surrounding code; minimal comments (one header comment per file or
  convention); bare `#endif` for short blocks.
- In shell, write simple things directly (no trivial wrappers), but give
  complex expressions (awk programs, nested substitutions) a named function
  and temporary values a named variable.

## Skills

Skills live in `.agents/skills/`. Read a skill's `SKILL.md` when the task
matches:

- `kc-patches`: patches fail or apply with fuzz; upgrading Tcl/Tk or a
  package; adding, refreshing, moving or removing `<pkg>/patches/*.diff`.
- `kc-tcl-upgrade`: upgrading or adding a Tcl/Tk version; smoke-testing a kit.
- `kc-new-package`: adding a package (C or Go extension, or pure Tcl).
