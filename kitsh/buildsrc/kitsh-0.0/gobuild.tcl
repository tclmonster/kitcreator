#
# gobuild.tcl --
#
#        Encapsulates Go/cgo build invocation for KitCreator.
#        Handles MSYS2 path conversion and CGO_CFLAGS/CGO_LDFLAGS
#        construction.
#
#        All inputs come via environment variables set by the Makefile.
#

proc getenv {name {default ""}} {
    if {[info exists ::env($name)]} {
        # Replace backslashes with forward slashes so that Tcl's
        # list parser does not interpret \b, \t, etc. in paths.
        return [string map {\\ /} $::env($name)]
    }
    return $default
}

# Convert a path via cygpath for MSYS2 mount resolution.
# Falls back to the original path if cygpath is unavailable.
# Uses open with explicit UTF-8 encoding since the native Windows
# tclkit may use a different system encoding than MSYS2 tools.
proc cvtpath {path} {
    if {![catch {
        set fd [open |[list cygpath -m $path] r]
        fconfigure $fd -encoding utf-8 -translation auto
        set result [string trim [read $fd]]
        close $fd
    }]} {
        return $result
    }
    return $path
}

proc cvtflag {flag} {
    return "[string range $flag 0 1][cvtpath [string range $flag 2 end]]"
}

set ::env(CGO_ENABLED) 1
set ::env(CC) [cvtpath [getenv CC cc]]

set goroot [getenv GOROOT ""]
if {$goroot ne ""} {
    set ::env(GOROOT) [cvtpath $goroot]
}

set ::env(CGO_CFLAGS) "-I[cvtpath [pwd]]"
foreach flag [concat [getenv CFLAGS] [getenv WISH_CFLAGS]] {
    if {$flag eq "-mwindows"} {
        continue
    }
    switch -glob -- $flag {
        -I* {
            append ::env(CGO_CFLAGS) " [cvtflag $flag]"
        }
        default {
            append ::env(CGO_CFLAGS) " $flag"
        }
    }
}

foreach flag [getenv CPPFLAGS] {
    switch -glob -- $flag {
        -I* {
            append ::env(CGO_CFLAGS) " [cvtflag $flag]"
        }
        default {
            # Skip other CPPFLAGS
        }
    }
}

set ::env(CGO_LDFLAGS) ""
foreach flag [getenv LDFLAGS] {
    switch -glob -- $flag {
        "/*" {
            # Bare absolute path (e.g. /clang64/lib/libdl.a)
            append ::env(CGO_LDFLAGS) " [cvtpath $flag]"
        }
        "-L*" {
            append ::env(CGO_LDFLAGS) " [cvtflag $flag]"
        }
        "-*" {
            # Pass through other linker flags
            append ::env(CGO_LDFLAGS) " $flag"
        }
        default {
            # Bare relative path — resolve against builddir
            append ::env(CGO_LDFLAGS) " [cvtpath [file join [pwd] $flag]]"
        }
    }
}

set go [cvtpath [getenv GO go]]
set go_output [cvtpath [getenv GO_OUTPUT]]

set cmd [list $go build -buildvcs=false -o $go_output]
set tags [string trim [getenv GO_BUILD_TAGS]]
if {$tags ne ""} {
    lappend cmd -tags $tags
}
lappend cmd .

cd [getenv GO_PKGDIR]
puts "gobuild.tcl: cd [pwd]"
puts "gobuild.tcl: CGO_CFLAGS=$::env(CGO_CFLAGS)"
puts "gobuild.tcl: CGO_LDFLAGS=$::env(CGO_LDFLAGS)"
puts "gobuild.tcl: exec $cmd"
exec {*}$cmd >@ stdout 2>@ stderr
