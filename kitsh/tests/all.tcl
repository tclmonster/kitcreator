# Runs the kitsh tests with a kit: <kit> all.tcl ?tcltest options?; exits 1 if any
# test failed
package require tcltest 2.5
::tcltest::configure -testdir [file dirname [file normalize [info script]]] {*}$argv

exit [::tcltest::runAllTests]
