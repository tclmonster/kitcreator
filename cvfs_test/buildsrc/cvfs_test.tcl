# CVFS test suite: package require cvfs_test; cvfs_test::run ?option value ...?
#
# Checks CVFS against manifest.tcl, written by mktree.tcl when the package was
# built: each path's type, size, mtime and contents; glob, access and open
# results recorded from the native tree; read-only errors; and concurrent first
# reads from several threads in a fresh process.  Tags such as F2 refer to the
# findings in the CVFS audit.  Exits non-zero on any failure (see -exit).
#
# Options:
#   -root dir        CVFS directory holding the tree (default: this package's tree)
#   -manifest file   manifest.tcl to check against (default: this package's)
#   -setup script    run first in the thread test's process and threads, to make
#                    -root available there (default: nothing; the kit mounts it)
#   -binary file     file to search for plaintext with -obfuscated (default: the kit)
#   -obfuscated 0|1  check that file contents are not stored as plain bytes
#   -threads n       threads in the thread test (default 16)
#   -repeat n        thread test runs, each in a new process (default 5)
#   -exit 0|1        exit when done (default 1); otherwise return the failure count

package require Tcl 8.6-

namespace eval ::cvfs_test {
	variable dir [file dirname [file normalize [info script]]]
	variable passed 0
	variable failed 0
}

proc ::cvfs_test::report {tag label ok {detail ""}} {
	variable passed
	variable failed

	if {$ok} {
		incr passed

		return 1
	}

	incr failed
	puts "FAIL \[$tag\] $label"
	if {$detail ne ""} {
		puts "    $detail"
	}

	return 0
}

proc ::cvfs_test::shorten {value} {
	if {[string length $value] > 200} {
		return "[string range $value 0 199]... ([string length $value] chars)"
	}

	return $value
}

proc ::cvfs_test::compare {tag label result expected} {
	report $tag $label [expr {$result eq $expected}] \
		"got: <[shorten $result]>\n    expected: <[shorten $expected]>"
}

# The first two words of the error code a script raises, or "ok".  When a
# handler raises a Tcl error instead of a POSIX one, tclvfs leaves errno alone
# and Tcl reports whatever an earlier failure set; a native ENOENT first stops
# a stale code from passing.
proc ::cvfs_test::error_code {script} {
	catch {open [file join [file dirname [info nameofexecutable]] cvfs_test-no-such-file]}

	if {[catch {uplevel 1 $script} result options]} {
		return [lrange [dict get $options -errorcode] 0 1]
	}

	return "ok"
}

proc ::cvfs_test::read_file {path} {
	set fd [open $path]
	fconfigure $fd -translation binary
	set data [read $fd]
	close $fd

	return $data
}

proc ::cvfs_test::path {root rel} {
	if {$rel eq ""} {
		return $root
	}

	return "$root/$rel"
}

proc ::cvfs_test::check_storage {root} {
	set fs [file system $root]

	report setup "$root is on CVFS" [string match "*::vfs::cvfs::*" $fs] "file system: $fs"
}

proc ::cvfs_test::check_entries {root entries} {
	set now [expr {[clock seconds] + 86400}]

	dict for {rel info} $entries {
		set path [path $root $rel]
		set type [dict get $info type]

		if {![report F8-F11 "reachable: $rel" [file exists $path]]} {
			continue
		}
		compare F8-F11 "type: $rel" [file type $path] $type

		# Built from the manifest's times; later if the kit build copied the tree
		set mtime [file mtime $path]
		set built [dict get $info mtime]
		report F1 "mtime: $rel" [expr {$mtime >= $built && $mtime <= $now}] \
			"mtime $mtime, built with $built"

		if {$type eq "directory"} {
			set children [list]
			foreach tail [lsort -unique [glob -nocomplain -tails -directory $path * .*]] {
				if {$tail ni {. ..}} {
					lappend children $tail
				}
			}
			compare F3,F9 "children: $rel" $children [dict get $info children]

			continue
		}

		compare F9-F11 "size: $rel" [file size $path] [dict get $info size]
		if {[catch {read_file $path} data]} {
			report read "read: $rel" 0 $data

			continue
		}
		compare read "contents: $rel" [zlib crc32 $data] [dict get $info crc]
	}
}

proc ::cvfs_test::check_cases {root manifest} {
	namespace eval case [dict get $manifest helpers]
	set case::root $root

	foreach case [dict get $manifest cases] expected [dict get $manifest expected] {
		lassign $case tag command

		if {[catch {namespace eval case $command} result]} {
			set result "error: $result"
		}
		set result [string map [list $root %ROOT%] $result]

		compare $tag $command $result $expected
	}

	namespace delete case
}

# Behaviour the native tree cannot show, since it is writable
proc ::cvfs_test::check_readonly {root} {
	set file [path $root lib/foo/a.txt]
	set dir [path $root lib]

	compare F7 "open directory" [error_code {open $dir}] {POSIX EISDIR}
	foreach mode {w a r+} {
		compare EROFS "open $mode" [error_code {open $file $mode}] {POSIX EROFS}
	}
	compare EROFS "file delete" [error_code {file delete $file}] {POSIX EROFS}
	compare EROFS "file mkdir" [error_code {file mkdir [path $root newdir]}] {POSIX EROFS}
	compare F15 "file mtime set" [error_code {file mtime $file 5}] {POSIX EROFS}
	compare EROFS "file attributes set" [error_code {file attributes $file -permissions 0o777}] {POSIX EROFS}
	compare F14 "writable file" [file writable $file] 0
	compare F14 "writable directory" [file writable $dir] 0

	# Same format as the native filesystem's -permissions
	compare F16 "permissions file" [file attributes $file -permissions] [format %0#5o 0o444]
	compare F16 "permissions directory" [file attributes $dir -permissions] [format %0#5o 0o40555]
}

proc ::cvfs_test::check_channels {root entries} {
	set path [path $root big.bin]
	set whole [read_file $path]

	set fd [open $path]
	fconfigure $fd -translation binary
	set chunks ""
	while {![eof $fd]} {
		append chunks [read $fd 4099]
	}
	compare read "chunked read" [zlib crc32 $chunks] [zlib crc32 $whole]

	seek $fd -10 end
	compare read "tell after seek" [tell $fd] [expr {[string length $whole] - 10}]
	compare read "read after seek" [read $fd] [string range $whole end-9 end]
	seek $fd 1000 start
	compare read "partial read" [read $fd 16] [string range $whole 1000 1015]
	close $fd

	set fd [open [path $root lines.txt]]
	set count 0
	while {[gets $fd line] >= 0} {
		incr count
	}
	close $fd
	compare read "gets lines" $count 20000

	compare read "empty file" [read_file [path $root empty.txt]] ""
}

# Several threads read the same files concurrently, each read the first in its
# process; run in a new process each time, so a crash is reported, not fatal.
# The threads wait on a lock the main thread holds, so they start together.
proc ::cvfs_test::check_threads {root entries setup threads repeat} {
	set files [list]
	set want [list]
	foreach rel {threads/a.bin threads/b.txt} {
		lappend files $rel
		lappend want [dict get $entries $rel size] [dict get $entries $rel crc]
	}

	set worker [join [list $setup [list set ::root $root] [list set ::files $files] {
		proc go {} {
			thread::rwmutex rlock $::gate
			thread::rwmutex unlock $::gate

			set ret [list]
			foreach rel $::files {
				set fd [open "$::root/$rel"]
				fconfigure $fd -translation binary
				set data [read $fd]
				close $fd
				lappend ret [string length $data] [zlib crc32 $data]
			}

			return $ret
		}
		thread::wait
	}] "\n"]

	set script [join [list $setup [list set worker $worker] [list set count $threads] [list set want $want] {
		package require Thread
		set gate [thread::rwmutex create]
		thread::rwmutex wlock $gate

		set ids [list]
		for {set idx 0} {$idx < $count} {incr idx} {
			lappend ids [thread::create "[list set ::gate $gate]\n$worker"]
		}
		foreach id $ids {
			thread::send -async $id go ::result($id)
		}
		after 500
		thread::rwmutex unlock $gate

		after 120000 {
			puts "timed out waiting for the threads"
			exit 1
		}
		while {[array size ::result] < [llength $ids]} {
			vwait ::result
		}
		set bad 0
		foreach id $ids {
			if {$::result($id) ne $want} {
				incr bad
				puts "thread read <$::result($id)>"
			}
		}
		exit [expr {$bad != 0}]
	}] "\n"]

	set fd [file tempfile scriptfile cvfs_test.tcl]
	puts $fd $script
	close $fd

	try {
		for {set run 1} {$run <= $repeat} {incr run} {
			set ok [expr {![catch {exec [info nameofexecutable] $scriptfile 2>@1} output]}]
			report F4 "threads: run $run of $repeat" $ok [string map [list \n "\n    "] $output]
		}
	} finally {
		file delete $scriptfile
	}
}

# File contents must not appear as plain bytes in the binary.  secret.bin is
# random, so compression stores it unchanged; only obfuscation hides it.
proc ::cvfs_test::check_obfuscation {root binary} {
	set needle [string range [read_file [path $root secret.bin]] 0 63]
	set haystack [read_file $binary]

	report obfuscation "secret.bin is not plaintext in $binary" [expr {[string first $needle $haystack] < 0}]
}

proc ::cvfs_test::run {args} {
	variable dir
	variable passed 0
	variable failed 0

	set options [dict create \
		-root       [file join $dir tree] \
		-manifest   [file join $dir manifest.tcl] \
		-setup      "" \
		-binary     [info nameofexecutable] \
		-obfuscated 0 \
		-threads    16 \
		-repeat     5 \
		-exit       1 \
	]
	if {[llength $args] % 2 != 0} {
		return -code error "wrong # args: should be \"cvfs_test::run ?option value ...?\""
	}
	foreach {option value} $args {
		if {![dict exists $options $option]} {
			return -code error "unknown option \"$option\": must be one of [join [dict keys $options] {, }]"
		}
		dict set options $option $value
	}
	set root [dict get $options -root]

	set fd [open [dict get $options -manifest]]
	fconfigure $fd -encoding utf-8
	set manifest [read $fd]
	close $fd
	set entries [dict get $manifest entries]

	if {[dict get $manifest platform] ne $::tcl_platform(platform)} {
		report setup "manifest platform" 0 \
			"built on [dict get $manifest platform], running on $::tcl_platform(platform)"
	}

	foreach {name script} [list \
		storage    {check_storage $root} \
		entries    {check_entries $root $entries} \
		cases      {check_cases $root $manifest} \
		readonly   {check_readonly $root} \
		channels   {check_channels $root $entries} \
		threads    {check_threads $root $entries [dict get $options -setup] [dict get $options -threads] [dict get $options -repeat]} \
		obfuscation {
			if {[dict get $options -obfuscated]} {
				check_obfuscation $root [dict get $options -binary]
			}
		} \
	] {
		if {[catch $script message]} {
			report $name "$name checks raised an error" 0 $message
		}
	}

	puts "cvfs_test: $passed passed, $failed failed"

	if {[dict get $options -exit]} {
		exit [expr {$failed != 0}]
	}

	return $failed
}

package provide cvfs_test 1.0
