# CVFS test suite: package require cvfs_test; cvfs_test::run ?option value ...?
#
# Runs the tcltest files in tests/ against this package's tree in the kit and
# exits 1 if any test failed.  Options are tcltest configure options, such as
# -match mtime-*, -verbose pass or -constraints encrypted.  To test another
# CVFS, pass -load with a script that mounts it and sets the variables listed
# in tests/common.tcl.

package require Tcl 8.6-
package require tcltest 2.5

namespace eval ::cvfs_test {
	variable dir [file dirname [file normalize [info script]]]
}

# Names of the files in tests/.  In a kit they are on the CVFS under test, where
# a broken glob could leave test files out and the suite still pass, so they
# come from the manifest, listed by mktree.tcl on the native filesystem.  A
# checkout's tests/ is native, so glob is safe there.
proc ::cvfs_test::test_files {} {
	variable dir

	if {[lindex [file system $dir] 0] eq "native"} {
		return [glob -tails -directory [file join $dir tests] *]
	}

	set fd [open [file join $dir manifest.tcl]]
	fconfigure $fd -encoding utf-8
	set manifest [read $fd]
	close $fd

	return [dict get $manifest tests]
}

# runAllTests also finds test files with glob, so it runs them from a native
# copy, made by name.  In one process, as only then does tcltest source the
# test files as UTF-8 (Tcl 8.6 would read a separate process's script in the
# system encoding); the copy is made with file mkdir, as the first test file's
# cleanupTests deletes what makeDirectory made
proc ::cvfs_test::run {args} {
	variable dir

	::tcltest::configure -singleproc 1 {*}$args

	set testdir [file join [::tcltest::temporaryDirectory] cvfs_test_files]
	file mkdir $testdir
	foreach file [test_files] {
		file copy -force [file join $dir tests $file] $testdir
	}
	::tcltest::configure -testdir $testdir

	set failed [::tcltest::runAllTests]
	file delete -force $testdir

	exit $failed
}

package provide cvfs_test 1.0
