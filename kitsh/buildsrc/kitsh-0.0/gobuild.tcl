#
# gobuild.tcl --
#
#        Encapsulates Go/cgo build invocation for KitCreator.
#        Handles MSYS2 path conversion, config.h define extraction,
#        and CGO_CFLAGS/CGO_LDFLAGS construction.
#
#        All inputs come via environment variables set by the Makefile.
#

proc getenv {name {default ""}} {
    if {[info exists ::env($name)]} {
        return $::env($name)
    }
    return $default
}

proc normalize {flag} {
    set pfx [string range $flag 0 1]
    set normpath [file normalize [string range $flag 2 end]]
    return "${pfx}${normpath}"
}

set ::env(CGO_ENABLED) 1

set ::env(CGO_CFLAGS) "-I[file normalize [pwd]]"
foreach flag [concat [getenv CFLAGS] [getenv WISH_CFLAGS]] {
    if {$flag eq "-mwindows"} {
        continue
    }
    switch -glob -- $flag {
        -I* {
            lappend ::env(CGO_CFLAGS) [normalize $flag]
        }
        default {
            lappend ::env(CGO_CFLAGS) $flag
        }
    }
}

foreach flag [getenv CPPFLAGS] {
    switch -glob -- $flag {
        -I* {
            lappend ::env(CGO_CFLAGS) [normalize $flag]
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
            # Bare absolute path (e.g. in MSYS2 /c/.../libfoo.a)
            lappend ::env(CGO_LDFLAGS) [file normalize $flag]
        }
        "-L*" {
            # Library may be absolute or relative path
            lappend ::env(CGO_LDFLAGS) [normalize $flag]
        }
        "-*" {
            # Pass through other linker flags
            lappend ::env(CGO_LDFLAGS) $flag
        }
        default {
            # Bare relative path should be normalized
            lappend ::env(CGO_LDFLAGS) [file normalize [file join [pwd] $flag]]
        }
    }
}

set cmd [list $::env(GO) build -buildvcs=false -o $::env(GO_OUTPUT)]
set tags [string trim $::env(GO_BUILD_TAGS)]
if {$tags ne ""} {
    lappend cmd -tags $tags
}
lappend cmd .

cd $::env(GO_PKGDIR)
puts "gobuild.tcl: cd [pwd]"
puts "gobuild.tcl: CGO_CFLAGS=$::env(CGO_CFLAGS)"
puts "gobuild.tcl: CGO_LDFLAGS=$::env(CGO_LDFLAGS)"
puts "gobuild.tcl: exec $cmd"
exec {*}$cmd >@ stdout 2>@ stderr
