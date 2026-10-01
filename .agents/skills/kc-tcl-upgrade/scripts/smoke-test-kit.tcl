# Usage: <kit> smoke-test-kit.tcl <workdir> <tbc-check> <package>...
#
# Run by smoke-test-kit.  Prints one line per check and exits 1 if any fails.

set failures 0

proc check {description passed} {
	if {$passed} {
		puts "ok    $description"
	} else {
		puts "FAIL  $description"
		incr ::failures
	}
}

proc inside_kit {path} {
	set kit [file normalize [info nameofexecutable]]
	set normalized_path [file normalize $path]
	set position [string first "$kit/" $normalized_path]

	return [expr {$position == 0}]
}

set packages [lassign $argv workdir tbc_check]

puts "Tcl [info patchlevel]: [info nameofexecutable]"

check "tcl_library is inside the kit: $tcl_library" [inside_kit $tcl_library]

set outside {}
foreach dir $auto_path {
	if {![inside_kit $dir]} {
		lappend outside $dir
	}
}
if {$outside eq {}} {
	check "auto_path is inside the kit" 1
} else {
	check "auto_path is inside the kit (outside: $outside)" 0
}

foreach package $packages {
	set failed [catch {package require $package} result]
	check "package require $package: $result" [expr {!$failed}]
}

set child [interp create]
set child_library [$child eval {set tcl_library}]
check "child tcl_library is inside the kit" [inside_kit $child_library]
foreach package $packages {
	set failed [catch {$child eval [list package require $package]} result]
	check "child package require $package: $result" [expr {!$failed}]
}
interp delete $child

if {$tbc_check} {
	set source [file join $workdir tbc-test.tcl]
	set compiled_source [file join $workdir tbc-test.tbc]
	set body {try { return "hi $name" } on error {message} { return $message }}

	set file [open $source w]
	puts $file [list proc greet {name} $body]
	puts $file {set ::greeting [greet kit]}
	close $file

	set failed [catch {
		package require tclcompiler
		compiler::compile $source
		source $compiled_source
	} result]

	if {$failed} {
		check "tclcompiler/tbcload round trip: $result" 0
	} else {
		check "tclcompiler/tbcload round trip: $::greeting" [expr {$::greeting eq {hi kit}}]

		set file [open $compiled_source]
		set compiled [read $file]
		close $file
		set body_found [expr {[string first {hi $name} $compiled] >= 0}]
		check "compiled proc body is not in the .tbc" [expr {!$body_found}]
	}
}

exit [expr {$failures > 0}]
