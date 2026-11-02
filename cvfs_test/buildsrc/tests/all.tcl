# Runs the CVFS tests: <tclsh> all.tcl ?tcltest options?
source [file join [file dirname [file dirname [file normalize [info script]]]] cvfs_test.tcl]

cvfs_test::run {*}$argv
