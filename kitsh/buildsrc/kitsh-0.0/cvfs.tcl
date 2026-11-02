#! /usr/bin/env tcl

package require vfs

namespace eval ::vfs::cvfs {}

# Convience functions
proc ::vfs::cvfs::Mount {hashkey local} {
	vfs::filesystem mount $local [list ::vfs::cvfs::vfshandler $hashkey]
	catch {
		vfs::RegisterMount $local [list ::vfs::cvfs::Unmount]
	}
}

proc ::vfs::cvfs::Unmount {local} {
	vfs::filesystem unmount $local
}

# Implementation
## I/O Handlers (pass to appropriate hashkey)
namespace eval ::vfs::cvfs::data {}
proc ::vfs::cvfs::data::getChildren args {
	set hashkey [lindex $args 0]

	set cmd "::vfs::cvfs::data::${hashkey}::getChildren"
	set cmd [linsert $args 0 $cmd]

	eval $cmd
}

proc ::vfs::cvfs::data::getMetadata args {
	set hashkey [lindex $args 0]

	set cmd "::vfs::cvfs::data::${hashkey}::getMetadata"
	set cmd [linsert $args 0 $cmd]

	eval $cmd
}

proc ::vfs::cvfs::data::getData args {
	set hashkey [lindex $args 0]

	set cmd "::vfs::cvfs::data::${hashkey}::getData"
	set cmd [linsert $args 0 $cmd]

	eval $cmd
}

## VFS and Chan I/O
### Dispatchers
proc ::vfs::cvfs::vfshandler {hashkey subcmd args} {
	set cmd $args
	set cmd [linsert $cmd 0 "::vfs::cvfs::vfsop_${subcmd}" $hashkey]

	return [eval $cmd]
}

proc ::vfs::cvfs::chanhandler {hashkey subcmd args} {
	set cmd $args
	set cmd [linsert $cmd 0 "::vfs::cvfs::chanop_${subcmd}" $hashkey]

	return [eval $cmd]
}

### Actual handlers
#### Channel operation handlers
proc ::vfs::cvfs::chanop_initialize {hashkey chanId mode} {
	return [list initialize finalize watch read seek]
}

proc ::vfs::cvfs::chanop_finalize {hashkey chanId} {
	unset -nocomplain ::vfs::cvfs::chandata([list $hashkey $chanId])

	return
}

proc ::vfs::cvfs::chanop_watch {hashkey chanId eventSpec} {
	array set chaninfo $::vfs::cvfs::chandata([list $hashkey $chanId])

	set chaninfo(watching) $eventSpec

	set ::vfs::cvfs::chandata([list $hashkey $chanId]) [array get chaninfo]

	if {[lsearch -exact $chaninfo(watching) "read"] != -1} {
		after 0 [list catch "chan postevent $chanId [list {read}]"]
	}

	return
}

proc ::vfs::cvfs::chanop_read {hashkey chanId bytes} {
	array set chaninfo $::vfs::cvfs::chandata([list $hashkey $chanId])

	set pos $chaninfo(pos)
	set len $chaninfo(len)

	if {[lsearch -exact $chaninfo(watching) "read"] != -1} {
		after 0 [list catch "chan postevent $chanId [list {read}]"]
	}

	if {$pos == $len} {
		return ""
	}

	set end [expr {$pos + $bytes}]
	if {$end > $len} {
		set end $len
	}

	set data [::vfs::cvfs::data::getData $hashkey $chaninfo(file) $pos $end]

	set dataLen [string length $data]
	incr pos $dataLen

	set chaninfo(pos) $pos

	set ::vfs::cvfs::chandata([list $hashkey $chanId]) [array get chaninfo]

	return $data
}

proc ::vfs::cvfs::chanop_seek {hashkey chanId offset origin} {
	array set chaninfo $::vfs::cvfs::chandata([list $hashkey $chanId])

	set pos $chaninfo(pos)
	set len $chaninfo(len)

	switch -- $origin {
		"start" - "0" {
			set pos $offset
		}
		"current" - "1" {
			set pos [expr {$pos + $offset}]
		}
		"end" - "2" {
			set pos [expr {$len + $offset}]
		}
	}

	if {$pos < 0} {
		set pos 0
	}

	if {$pos > $len} {
		set pos $len
	}

	set chaninfo(pos) $pos
	set ::vfs::cvfs::chandata([list $hashkey $chanId]) [array get chaninfo]

	return $pos
}

#### VFS operation handlers
proc ::vfs::cvfs::vfsop_stat {hashkey root relative actualpath} {
	if {[catch {::vfs::cvfs::data::getMetadata $hashkey $relative} ret]} {
		vfs::filesystem posixerror $::vfs::posix(ENOENT)
	}

	return $ret
}

# mode is a mask of R_OK 4, W_OK 2 and X_OK 1 (Tcl_FSAccess.3); files are 0444
# and directories 0555
proc ::vfs::cvfs::vfsop_access {hashkey root relative actualpath mode} {
	if {[catch {::vfs::cvfs::data::getMetadata $hashkey $relative} ret]} {
		vfs::filesystem posixerror $::vfs::posix(ENOENT)
	}
	array set metadata $ret

	if {$mode & 0x2} {
		vfs::filesystem posixerror $::vfs::posix(EROFS)
	}

	if {($mode & 0x1) && $metadata(type) ne "directory"} {
		vfs::filesystem posixerror $::vfs::posix(EACCES)
	}

	return 1
}

# types is a mask of TCL_GLOB_TYPE_* bits (Tcl_FSMatchInDirectory.3); any of
# them may match, and 0 means any type
proc ::vfs::cvfs::matchtype {type types} {
	if {$types == 0} {
		return 1
	}

	switch -- $type {
		"directory" {
			set bit 0x04
		}
		"file" {
			set bit 0x10
		}
		default {
			return 0
		}
	}

	return [expr {($types & $bit) != 0}]
}

# Follows Tcl_FSMatchInDirectory.3: results include the caller's path prefix;
# no match, or a missing directory, is an empty result.  An empty pattern
# checks the path itself.  tclvfs handles TCL_GLOB_TYPE_MOUNT, and kitcreator's
# tclvfs applies glob's Unix hidden-file rule and the -types permissions to
# what this returns (tclvfs/patches/tclvfs-1.5.0-glob-hidden-and-permissions.diff).
proc ::vfs::cvfs::vfsop_matchindirectory {hashkey root relative actualpath pattern types} {
	if {[catch {::vfs::cvfs::data::getMetadata $hashkey $relative} ret]} {
		return [list]
	}
	array set metadata $ret

	if {$pattern eq ""} {
		if {[matchtype $metadata(type) $types]} {
			return [list $actualpath]
		}

		return [list]
	}

	if {$metadata(type) ne "directory"} {
		return [list]
	}

	if {[string index $actualpath end] ne "/"} {
		append actualpath "/"
	}

	set ret [list]
	foreach child [::vfs::cvfs::data::getChildren $hashkey $relative] {
		# By string, as file tail treats a leading "~" specially in Tcl 8.6
		set tail [string range $child [expr {[string last "/" $child] + 1}] end]

		if {![string match $pattern $tail]} {
			continue
		}

		if {[catch {::vfs::cvfs::data::getMetadata $hashkey $child} childmetadata]} {
			continue
		}

		if {![matchtype [dict get $childmetadata type] $types]} {
			continue
		}

		lappend ret "${actualpath}${tail}"
	}

	return $ret
}

proc ::vfs::cvfs::vfsop_fileattributes {hashkey root relative actualpath {index -1} {value ""}} {
	set attrs [list -owner -group -permissions]

	if {$value != ""} {
		vfs::filesystem posixerror $::vfs::posix(EROFS)
	}

	if {$index == -1} {
		return $attrs
	}

	if {[catch {::vfs::cvfs::data::getMetadata $hashkey $relative} ret]} {
		vfs::filesystem posixerror $::vfs::posix(ENOENT)
	}
	array set metadata $ret

	set attr [lindex $attrs $index]

	switch -- $attr {
		"-owner" {
			return $metadata(uid)
		}
		"-group" {
			return $metadata(gid)
		}
		"-permissions" {
			# The mode includes the type bits; same format as the native
			# filesystem's -permissions
			return [format {%0#5o} $metadata(mode)]
		}
	}

	return -code error "Invalid index"
}

proc ::vfs::cvfs::vfsop_open {hashkey root relative actualpath mode permissions} {
	if {$mode != "" && $mode != "r"} {
		vfs::filesystem posixerror $::vfs::posix(EROFS)
	}

	if {[catch {::vfs::cvfs::data::getMetadata $hashkey $relative} ret]} {
		vfs::filesystem posixerror $::vfs::posix(ENOENT)
	}
	array set metadata $ret

	if {$metadata(type) == "directory"} {
		vfs::filesystem posixerror $::vfs::posix(EISDIR)
	}

	set chan [chan create [list "read"] [list ::vfs::cvfs::chanhandler $hashkey]]

	set ::vfs::cvfs::chandata([list $hashkey $chan]) [list file $relative pos 0 len $metadata(size) watching ""]

	return [list $chan]
}

##### No-Ops since we are a readonly filesystem
proc ::vfs::cvfs::vfsop_createdirectory {args} {
	vfs::filesystem posixerror $::vfs::posix(EROFS)
}
proc ::vfs::cvfs::vfsop_deletefile {args} {
	vfs::filesystem posixerror $::vfs::posix(EROFS)
}
proc ::vfs::cvfs::vfsop_removedirectory {args} {
	vfs::filesystem posixerror $::vfs::posix(EROFS)
}
proc ::vfs::cvfs::vfsop_utime {args} {
	vfs::filesystem posixerror $::vfs::posix(EROFS)
}

package provide vfs::cvfs 1.0
