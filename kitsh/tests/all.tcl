# Runs the kitsh tests with a kit: <kit> all.tcl ?tcltest options?; exits 1 if any
# test failed.  In one process, as only then does tcltest source the test
# files as UTF-8 (Tcl 8.6 would read a separate process's script in the system
# encoding)
package require tcltest 2.5
::tcltest::configure -singleproc 1 -testdir [file dirname [file normalize [info script]]] {*}$argv

exit [::tcltest::runAllTests]
