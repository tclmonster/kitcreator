# Shared by the test files: settings, the manifest and helpers.  The tcltest
# -load script may set these in ::cvfs_test first: root (CVFS directory holding
# the tree), manifest_file, binary (searched by obfuscation.test), and threads
# and repeat (threads.test).

::tcltest::loadTestedCommands

namespace eval ::cvfs_test {}

apply {{} {
	if {![info exists ::cvfs_test::root]} {
		package require cvfs_test

		set ::cvfs_test::root [file join $::cvfs_test::dir tree]
		set ::cvfs_test::manifest_file [file join $::cvfs_test::dir manifest.tcl]
	}

	foreach {name value} [list \
		binary        [info nameofexecutable] \
		threads       16 \
		repeat        5 \
	] {
		if {![info exists ::cvfs_test::$name]} {
			set ::cvfs_test::$name $value
		}
	}

	if {![info exists ::cvfs_test::manifest]} {
		set fd [open $::cvfs_test::manifest_file]
		fconfigure $fd -encoding utf-8
		set ::cvfs_test::manifest [read $fd]
		close $fd
	}
}}

proc ::cvfs_test::path {rel} {
	variable root

	if {$rel eq ""} {
		return $root
	}

	return "$root/$rel"
}

proc ::cvfs_test::read_file {path} {
	set fd [open $path]
	fconfigure $fd -translation binary
	set data [read $fd]
	close $fd

	return $data
}

proc ::cvfs_test::children {path} {
	set ret [list]
	foreach tail [lsort -unique [glob -nocomplain -tails -directory $path * .*]] {
		if {$tail ni {. ..}} {
			lappend ret $tail
		}
	}

	return $ret
}

# When a handler raises a Tcl error instead of a POSIX one, tclvfs leaves errno
# alone and Tcl reports whatever an earlier failure set; a native ENOENT first
# stops a stale error code from passing
proc ::cvfs_test::clear_errno {} {
	catch {open [file join [file dirname [info nameofexecutable]] cvfs_test-no-such-file]}
}
