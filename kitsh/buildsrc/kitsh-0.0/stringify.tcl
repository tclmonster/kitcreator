#! /usr/bin/env tclsh

# Writes each file as C string literals, one per line
proc stringifyfile {filename} {
	set fd [open $filename]
	fconfigure $fd -encoding utf-8
	set data [read -nonewline $fd]
	close $fd

	set ret ""
	foreach line [split $data \n] {
		set line [string map [list "\\" "\\\\" "\"" "\\\""] $line]
		append ret "\t\"$line\\n\"\n"
	}

	return $ret
}

fconfigure stdout -encoding utf-8 -translation lf

foreach file $argv {
	puts -nonewline [stringifyfile $file]
}

exit 0
