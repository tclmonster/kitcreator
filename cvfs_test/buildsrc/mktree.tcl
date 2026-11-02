# Generates the CVFS test tree and manifest: mktree.tcl <outdir>
#
# <outdir>/tree is compiled into the kit.  <outdir>/manifest.tcl records each
# path's type, size, mtime and CRC, and the results of glob, access and open
# cases run here against the native tree, for tests/*.test to repeat against
# CVFS, and the names of the test files.  Names Windows cannot store, and
# symbolic links, are Unix only.  This file is UTF-8: on Tcl 8.6 run it with
# "tclsh -encoding utf-8", or the names below are read in the system encoding.

package require Tcl 8.6-

if {[llength $argv] != 1} {
	puts stderr "Usage: mktree.tcl <outdir>"

	exit 1
}

set outdir [file normalize [lindex $argv 0]]
set root [file join $outdir tree]
set unix [expr {$tcl_platform(platform) eq "unix"}]

if {[file exists $root]} {
	puts stderr "$root already exists"

	exit 1
}

# Fixed seed, so every build has the same contents
expr {srand(20261102)}

proc random_bytes {count} {
	set values [list]
	for {set idx 0} {$idx < $count} {incr idx} {
		lappend values [expr {int(256 * rand())}]
	}

	return [binary format c* $values]
}

proc text_lines {count} {
	set ret ""
	for {set idx 1} {$idx <= $count} {incr idx} {
		append ret "line $idx of $count\n"
	}

	return $ret
}

proc native_path {rel} {
	global root

	return [file join $root {*}[split $rel "/"]]
}

proc write_file {rel data} {
	set path [native_path $rel]

	file mkdir [file dirname $path]
	set fd [open $path w]
	fconfigure $fd -translation binary
	puts -nonewline $fd $data
	close $fd
}

# "ab" and "bR" have the same cvfs_hash; threads/ is read only by the thread test
set files [dict create \
	empty.txt                  "" \
	lines.txt                  [text_lines 20000] \
	big.bin                    [random_bytes 300000] \
	secret.bin                 [random_bytes 4096] \
	.htaccess                  "deny from all\n" \
	.well-known/acme/token     "token\n" \
	ab                         "ab\n" \
	bR                         "bR\n" \
	"café.txt"                 "cafe\n" \
	"déjà/vu.txt"              "deja vu\n" \
	"日本.txt"                 "nihon\n" \
	{sp ace/f g.txt}           "spaces\n" \
	{c++/x.h}                  "plus\n" \
	{a(b)/p.txt}               "parentheses\n" \
	{x[y]/q.txt}               "brackets\n" \
	{{br}/r.txt}               "braces\n" \
	{x+y/inner/deep.txt}       "nested\n" \
	lib/tk.tcl                 "# tk\n" \
	lib/tkx.tcl                "# tkx\n" \
	lib/foo/a.txt              "a\n" \
	lib/foo/bar/b.txt          "b\n" \
	threads/a.bin              [random_bytes 1048576] \
	threads/b.txt              [text_lines 50000] \
]

if {$unix} {
	dict set files {q"uote.txt}     "quote\n"
	dict set files {back\slash.txt} "backslash\n"
	dict set files {what??=.txt}    "trigraph\n"
	dict set files "tab\tname.txt"  "tab\n"
	dict set files {st*r.txt}       "star\n"
	dict set files {col:on.txt}     "colon\n"
}

dict for {rel data} $files {
	write_file $rel $data
}
file mkdir [native_path emptydir]

if {$unix} {
	file link -symbolic [native_path dirlink] lib
	file link -symbolic [native_path link.txt] lib/foo/a.txt
}

# Distinct fixed times, set after everything is created; directories last,
# since creating entries changes a directory's mtime
proc real_paths {dir} {
	set ret [list]
	foreach path [lsort -unique [glob -nocomplain -directory $dir * .*]] {
		if {[file tail $path] in {. ..} || [file type $path] eq "link"} {
			continue
		}
		if {[file isdirectory $path]} {
			lappend ret {*}[real_paths $path]
		}
		lappend ret $path
	}

	return $ret
}

set mtime 1000000000
foreach path [list {*}[real_paths $root] $root] {
	if {$unix} {
		file attributes $path -permissions [expr {[file isdirectory $path] ? 0o755 : 0o644}]
	}
	catch {
		file mtime $path [incr mtime 3600]
	}
}

# Manifest entries, following symbolic links as dir2c.tcl does
proc walk {dir rel} {
	global entries

	set children [list]
	foreach tail [lsort -unique [glob -nocomplain -tails -directory $dir * .*]] {
		if {$tail in {. ..}} {
			continue
		}
		lappend children $tail

		set path [file join $dir $tail]
		set childrel [expr {$rel eq "" ? $tail : "$rel/$tail"}]
		file stat $path info

		if {$info(type) eq "directory"} {
			walk $path $childrel
		} else {
			set fd [open $path]
			fconfigure $fd -translation binary
			set data [read $fd]
			close $fd

			dict set entries $childrel [dict create type file size $info(size) mtime $info(mtime) crc [zlib crc32 $data]]
		}
	}

	file stat $dir info
	dict set entries $rel [dict create type directory mtime $info(mtime) children $children]
}

set entries [dict create]
walk $root ""

# Case helpers, stored in the manifest so cases.test uses the same ones
set helpers {
	variable root

	proc D {dir} {
		variable root

		if {$dir eq ""} {
			return $root
		}

		return "$root/$dir"
	}

	proc T {types} {
		if {$types eq ""} {
			return [list]
		}

		return [list -types $types]
	}

	proc glob_tails {dir pattern types} {
		lsort [glob -nocomplain -tails {*}[T $types] -directory [D $dir] $pattern]
	}

	proc glob_full {dir pattern types} {
		lsort [glob -nocomplain {*}[T $types] -directory [D $dir] $pattern]
	}

	proc glob_self {types} {
		lsort [glob -nocomplain {*}[T $types] [D ""]]
	}

	proc glob_join {args} {
		lsort [glob -nocomplain -directory [D ""] -join {*}$args]
	}

	proc glob_in {dir pattern} {
		set saved [pwd]
		cd [D $dir]
		try {
			lsort [glob -nocomplain $pattern]
		} finally {
			cd $saved
		}
	}

	proc exists {path} {
		file exists [D $path]
	}

	proc readable {path} {
		file readable [D $path]
	}

	proc executable {path} {
		file executable [D $path]
	}

	proc open_error {path} {
		if {[catch {open [D $path]} fd options]} {
			return [lrange [dict get $options -errorcode] 0 1]
		}
		close $fd

		return "ok"
	}
}

namespace eval case $helpers
set case::root $root

# Cases: {tags command}.  Native ".*" also lists "." and ".."; glob.n says
# they must be matched explicitly, and VFSes do not return them, so they are
# dropped from the expected results.
set cases [list]

set glob_dirs [list \
	"" *  "" .*  "" b*  "" {[ab]*}  "" ?b  "" caf*  "" d*  "" *.txt \
	"" {\{br\}}  "" {x\[y\]}  "" {a(b)}  "" {c++}  "" {sp ace} \
	lib *  lib tk*  lib {tk?.tcl}  lib/foo *  lib/foo/bar *  emptydir * \
	.well-known *  .well-known/acme *  {sp ace} *  {c++} *  {a(b)} * \
	{x[y]} *  {{br}} *  x+y *  threads * \
	nodir *  empty.txt *  lib/foo/.. * \
]
if {$unix} {
	lappend glob_dirs "" {q"*}  "" {back\\*}  "" {what\?\?=*}  "" {st\*r*}  "" {col:on*}  dirlink *
}

foreach {dir pattern} $glob_dirs {
	foreach types {{} f d {f d}} {
		lappend cases [list F2,F5,F6,F7,F18 [list glob_tails $dir $pattern $types]]
		lappend cases [list F2,F5,F6,F7,F18 [list glob_full $dir $pattern $types]]
	}
}

foreach types {{} f d} {
	lappend cases [list F5,F6 [list glob_self $types]]
}
lappend cases [list F2,F6 [list glob_join * *.txt]]
lappend cases [list F2,F6 [list glob_tails "" */*/* {}]]
lappend cases [list F6 [list glob_in lib foo/*]]
lappend cases [list F6 [list glob_in lib/foo *]]

foreach path [list lib empty.txt big.bin .htaccess "café.txt" {sp ace/f g.txt} nope nodir/nope] {
	lappend cases [list F7,F14 [list exists $path]]
	lappend cases [list F14 [list readable $path]]
}
foreach path {nope nodir/nope lib/foo/a.txt} {
	lappend cases [list F7 [list open_error $path]]
}
lappend cases [list F14 [list executable lib/foo/a.txt]]
lappend cases [list F14 [list executable lib]]

proc without_dots {list} {
	set ret [list]
	foreach item $list {
		if {[file tail $item] in {. ..}} {
			continue
		}
		lappend ret $item
	}

	return $ret
}

set expected [list]
foreach case $cases {
	set command [lindex $case 1]

	if {[catch {namespace eval case $command} result]} {
		set result "error: $result"
	} elseif {[string match glob_* [lindex $command 0]]} {
		set result [without_dots $result]
	}

	lappend expected [string map [list $root %ROOT%] $result]
}

# In a kit, tests/ is on the CVFS under test, where a broken glob could leave
# test files out unnoticed, so cvfs_test::run takes their names from here
set tests [lsort [glob -tails -directory [file join [file dirname [file normalize [info script]]] tests] *]]

set fd [open [file join $outdir manifest.tcl] w]
fconfigure $fd -encoding utf-8 -translation lf
puts $fd [list platform $tcl_platform(platform) entries $entries helpers $helpers cases $cases expected $expected tests $tests]
close $fd
