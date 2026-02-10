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

set mwindows 0
set ::env(CGO_CFLAGS) "-I[cvtpath [pwd]]"
foreach flag [concat [getenv CFLAGS] [getenv WISH_CFLAGS] [getenv GOKIT_CFLAGS]] {
    if {$flag eq "-mwindows"} {
        # Linker flag, not a compiler flag — redirect to CGO_LDFLAGS
        # so Go produces a Windows GUI subsystem binary.
        set mwindows 1
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

# Process CPPFLAGS: convert -I paths and pass -D defines through.
# Use the raw env value and regexp (not Tcl list parsing via foreach)
# because -D values may contain backslash-escaped quotes and spaces
# (e.g. -DPACKAGE_STRING=\"kitsh 0.0\") that would be corrupted.
if {[info exists ::env(CPPFLAGS)]} {
    set raw $::env(CPPFLAGS)

    # Convert -I paths via cygpath
    foreach {match path} [regexp -all -inline -- {-I(\S+)} [string map {\\ /} $raw]] {
        append ::env(CGO_CFLAGS) " -I[cvtpath $path]"
    }

    # Extract non-I flags (primarily -D defines from @DEFS@).
    set defs [regsub -all -- {-I\S+} $raw {}]

    # Remove backslash before space — a shell escape artifact.
    # @DEFS@ uses \"  and \<space> for shell escaping.  The Makefile
    # recipe wraps $(CPPFLAGS) in double quotes for the env-var
    # assignment, so the shell converts \" -> " but leaves \<space>
    # as literal backslash + space.
    set defs [string map [list "\\ " " "] $defs]

    # Wrap -D flags whose values contain double quotes in single
    # quotes so that Go's quoted.Split (which only recognises quotes
    # at the START of a token) keeps them as single tokens.
    set defs [regsub -all -- {-D\w+="[^"]*"} $defs {'&'}]

    set defs [string trim $defs]
    if {$defs ne ""} {
        append ::env(CGO_CFLAGS) " $defs"
    }
}

# Build linker flags for -extldflags instead of CGO_LDFLAGS.
# Go collects CGO_LDFLAGS per cgo-using package and combines them
# at link time, so archives appear once per package — causing
# "multiple definition" errors with --whole-archive on GNU ld.
# Using -extldflags passes flags once to the external linker.
set extldflags ""
set ldflags [getenv LDFLAGS]
for {set i 0} {$i < [llength $ldflags]} {incr i} {
    set flag [lindex $ldflags $i]
    switch -glob -- $flag {
        "/*" {
            # Bare absolute path (e.g. /clang64/lib/libdl.a)
            append extldflags " [cvtpath $flag]"
        }
        "-L*" {
            set lpath [string range $flag 2 end]
            if {[file pathtype $lpath] ne "absolute"} {
                set lpath [file normalize $lpath]
            }
            append extldflags " -L[cvtpath $lpath]"
        }
        "-framework" {
            # macOS: -framework takes the next word as its argument
            append extldflags " $flag"
            incr i
            if {$i < [llength $ldflags]} {
                append extldflags " [lindex $ldflags $i]"
            }
        }
        "-*" {
            # Pass through other linker flags
            append extldflags " $flag"
        }
        default {
            # Bare relative path — resolve against builddir
            append extldflags " [cvtpath [file join [pwd] $flag]]"
        }
    }
}
if {$mwindows} {
    append extldflags " -mwindows"
}
set ::env(CGO_LDFLAGS) ""

set go [cvtpath [getenv GO go]]
set go_output [cvtpath [getenv GO_OUTPUT]]

set cmd [list $go build -buildvcs=false -o $go_output]
set buildmode [getenv GO_BUILDMODE ""]
if {$buildmode ne ""} {
    lappend cmd -buildmode $buildmode
}
set extldflags [string trim $extldflags]
if {$extldflags ne ""} {
    lappend cmd -ldflags "-extldflags \"$extldflags\""
}
set tags [string trim [getenv GO_BUILD_TAGS]]
if {$tags ne ""} {
    lappend cmd -tags $tags
}
lappend cmd .

cd [getenv GO_PKGDIR]
puts "gobuild.tcl: cd [pwd]"
puts "gobuild.tcl: CGO_CFLAGS=$::env(CGO_CFLAGS)"
puts "gobuild.tcl: extldflags=$extldflags"
puts "gobuild.tcl: exec $cmd"
exec {*}$cmd >@ stdout 2>@ stderr
