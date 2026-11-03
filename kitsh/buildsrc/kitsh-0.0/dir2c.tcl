#! /usr/bin/env tclsh

set encrypt  0
set compress 0
foreach arg {encrypt compress} {
	set found [lsearch $argv "--${arg}"]
	if {$found != -1} {
		set ${arg} 1
		set argv [lreplace $argv $found $found]
	}
}

if {[llength $argv] != 2} {
	puts stderr "Usage: dir2c.tcl <hashkey> <startdir> \[--encrypt\] \[--compress\]"

	exit 1
}

set hashkey [lindex $argv 0]
set startdir [lindex $argv 1]

# Unix file names are bytes, nearly always UTF-8; without a UTF-8 locale Tcl
# would decode them as iso8859-1 and the kit would store them double-encoded
if {$tcl_platform(platform) eq "unix"} {
	encoding system utf-8
}

proc shorten_file {dir file} {
	set dirNameLen [string length $dir]

	if {[string range $file 0 [expr {$dirNameLen - 1}]] == $dir} {
		set file [string range $file $dirNameLen end]
	}

	if {[string index $file 0] == "/"} {
		set file [string range $file 1 end]
	}
	return $file
}

# Path of a directory with every symbolic link resolved, including its last
# component (file normalize leaves the last one alone)
proc real_dir {dir} {
	return [file dirname [file normalize [file join $dir __real_dir__]]]
}

proc recursive_glob {dir {ancestors {}}} {
	lappend ancestors [real_dir $dir]

	# ".*" for dotfiles, which "*" skips on Unix but not on Windows; sorted so
	# every build of the same tree produces the same output
	set children [lsort -unique [glob -nocomplain -directory $dir * .*]]

	set ret [list $dir]
	foreach child $children {
		if {[file tail $child] in {. ..}} {
			continue
		}

		unset -nocomplain childinfo
		catch {
			file stat $child childinfo
		}

		if {![info exists childinfo(type)]} {
			continue
		}

		if {$childinfo(type) == "directory"} {
			if {[real_dir $child] in $ancestors} {
				error "directory loop at $child"
			}

			foreach add [recursive_glob $child $ancestors] {
				lappend ret $add
			}

			continue
		}

		if {$childinfo(type) != "file"} {
			continue
		}

		lappend ret $child
	}

	return $ret
}

# Quote a file name as a C string literal of its UTF-8 bytes; octal escapes
# for quotes, backslashes, "?" (trigraphs) and bytes outside printable ASCII
proc cname {name} {
	set ret "\""
	foreach byte [split [encoding convertto utf-8 $name] ""] {
		scan $byte %c code
		if {$code < 32 || $code > 126 || $byte in {\" \\ ?}} {
			append ret [format {\%03o} $code]
		} else {
			append ret $byte
		}
	}
	append ret "\""

	return $ret
}

# Convert a string into a C-style binary string
## XXX: This function needs to be optimized
proc stringify {data} {
	set ret "\""
	for {set idx 0} {$idx < [string length $data]} {incr idx} {
		binary scan [string index $data $idx] H* char

		append ret "\\x${char}"

		if {($idx % 20) == 0 && $idx != 0} {
			append ret "\"\n\""
		}
	}

	set ret [string trim $ret "\n\""]

	set ret "\"$ret\""

	return $ret
}

# A byte string as a C array initializer
proc cbytes {bytes} {
	binary scan $bytes cu* values

	set ret [list]
	foreach value $values {
		lappend ret [format 0x%02x $value]
	}

	return "{[join $ret {, }]}"
}

# Associated data binding an encrypted name to its index, and a file's
# contents to its inflated size and path; cvfs_name and cvfs_decode_encrypted
# build the same strings
proc name_ad {index} {
	return [encoding convertto utf-8 "name:$index"]
}

proc data_ad {size_inflated path} {
	return [encoding convertto utf-8 "data:$size_inflated:$path"]
}

# This function must be kept in-sync with the generated C function below
proc cvfs_hash {path} {
	set h 0
	set g 0

	binary scan [encoding convertto utf-8 $path] cu* bytes
	foreach char $bytes {
		set h [expr {($h << 4) + $char}]
		set g [expr {$h & 0xf0000000}]
		if {$g != 0} {
			set h [expr {($h & 0xffffffff) ^ ($g >> 24)}]
		}

		set h [expr {$h & ((~$g) & 0xffffffff)}]
	}

	return $h
}

# Keys for an encrypted VFS: one for contents and names, one for the index of
# path tags.  New for every build; they end up in the generated C
if {$encrypt} {
	if {[catch {package require monocypher}]} {
		puts stderr "dir2c.tcl: --encrypt needs the monocypher package in this tclsh (a kit built with --enable-monocypher)"

		exit 1
	}

	set data_key [monocypher::key new -random]
	set index_key [monocypher::key new -random]
}

# Generate list of files to include in output
set files [recursive_glob $startdir]

# Insert dummy entry cooresponding to C dummy entry
set files [linsert $files 0 "__DUMMY__"]

# Produce C89 compatible header
set cpp_tag "CVFS_[string toupper $hashkey]"
set code_tag "cvfs_[string tolower $hashkey]"
set hashkey [string tolower $hashkey]

puts "#ifndef $cpp_tag"
puts "#  define $cpp_tag 1"
if {$encrypt} {
	puts "#  define CVFS_ENCRYPTED 1"
	puts "#  include <stdlib.h>"
	puts "#  include <string.h>"
	puts "#  include \"monocypher/monocypher.h\""
}
puts {
#  ifdef HAVE_STDC
#    ifndef HAVE_UNISTD_H
#      define HAVE_UNISTD_H 1
#    endif
#    ifndef HAVE_STRING_H
#      define HAVE_STRING_H 1
#    endif
#    ifndef HAVE_STDLIB_H
#      define HAVE_STDLIB_H 1
#    endif
#  endif
#  ifdef HAVE_UNISTD_H
#    include <unistd.h>
#  endif
#  ifdef HAVE_STRING_H
#    include <string.h>
#  endif
#  ifdef HAVE_STDLIB_H
#    include <stdlib.h>
#  endif
/* Without TCL_THREADS, Tcl 8.6's tcl.h makes Tcl_MutexLock a no-op even when
 * Tcl has threads; a Tcl without threads still provides it, doing nothing */
#  ifndef TCL_THREADS
#    define TCL_THREADS 1
#  endif
#  include <tcl.h>

#  ifndef LOADED_CVFS_COMMON
#    define LOADED_CVFS_COMMON 1

/* Tcl 8.6 compatibility for Tcl 9 Tcl_Size type */
#    include <limits.h>
#    ifndef TCL_SIZE_MAX
#      ifndef Tcl_Size
         typedef int Tcl_Size;
#      endif
#      define TCL_SIZE_MAX INT_MAX
#      define TCL_SIZE_MODIFIER ""
#    endif

typedef enum {
	CVFS_FILETYPE_FILE            = 1,
	CVFS_FILETYPE_DIR             = 2,
	CVFS_FILETYPE_ENCRYPTED_FILE  = 4,
	CVFS_FILETYPE_COMPRESSED_FILE = 8,
} cvfs_filetype_t;

/* In an encrypted VFS, name is NULL and name_box holds the name, and data
 * holds the (compressed) contents, each as a box: a version byte (1), a
 * 24-byte nonce, a 16-byte tag and the XChaCha20-Poly1305 ciphertext, as the
 * monocypher package's encrypt method makes */
struct cvfs_data {
	const char *             name;
	unsigned long            index;
	Tcl_Size                 size;
	Tcl_Size                 size_inflated;
	Tcl_WideInt              mtime;
	cvfs_filetype_t          type;
	const unsigned char *    data;
	int                      free;
	const unsigned char *    name_box;
	Tcl_Size                 name_box_size;
	unsigned long            first_child;
	unsigned long            num_children;
};

/* An encrypted VFS's index: the keyed BLAKE2b tag of each path, sorted */
struct cvfs_index_entry {
	unsigned char            tag[16];
	unsigned long            index;
};

#    define CVFS_BOX_VERSION  1
#    define CVFS_BOX_NONCE    1
#    define CVFS_BOX_TAG      25
#    define CVFS_BOX_OVERHEAD 41

#    ifndef CVFS_ENCRYPTED
static unsigned long cvfs_hash(const unsigned char *path) {
	unsigned long i, h = 0, g = 0;

	for (i = 0; path[i]; i++) {
		h = (h << 4) + path[i];
		g = h & 0xf0000000;
		if (g) {
			h ^= (g >> 24);
		}
		h &= ((~g) & 0xffffffffLU);
	}

	return(h);
}
#    endif

#    ifdef CVFS_ENCRYPTED
/* Opens a box into out (box_size - CVFS_BOX_OVERHEAD bytes); 0 on success.
 * On failure crypto_aead_unlock has not written to out */
static int cvfs_box_open(unsigned char *out, const unsigned char *box, Tcl_Size box_size, const unsigned char *key, Tcl_Obj *ad) {
	const unsigned char *ad_bytes;
	Tcl_Size ad_size;

	if (box_size < CVFS_BOX_OVERHEAD || box[0] != CVFS_BOX_VERSION) {
		return(-1);
	}

	ad_bytes = (const unsigned char *) Tcl_GetStringFromObj(ad, &ad_size);

	return(crypto_aead_unlock(out, box + CVFS_BOX_TAG, key, box + CVFS_BOX_NONCE, ad_bytes, (size_t) ad_size,
	    box + CVFS_BOX_OVERHEAD, (size_t) (box_size - CVFS_BOX_OVERHEAD)));
}

/* Wipes and releases a plaintext byte array, which must be unshared */
static void cvfs_free_plain(Tcl_Obj *plain) {
	unsigned char *bytes;
	Tcl_Size length;

	bytes = Tcl_GetByteArrayFromObj(plain, &length);
	crypto_wipe(bytes, (size_t) length);
	Tcl_DecrRefCount(plain);
}

/* Decrypts an entry's name into a new byte array (its UTF-8 bytes) with a
 * reference held, for cvfs_free_plain; NULL if it does not decrypt */
static Tcl_Obj *cvfs_name(const struct cvfs_data *finfo, const unsigned char *key) {
	Tcl_Obj *name, *ad;
	int status;

	if (finfo->name_box_size < CVFS_BOX_OVERHEAD) {
		return(NULL);
	}

	name = Tcl_NewByteArrayObj(NULL, finfo->name_box_size - CVFS_BOX_OVERHEAD);
	Tcl_IncrRefCount(name);
	ad = Tcl_ObjPrintf("name:%lu", finfo->index);
	Tcl_IncrRefCount(ad);

	status = cvfs_box_open(Tcl_GetByteArrayFromObj(name, NULL), finfo->name_box, finfo->name_box_size, key, ad);
	Tcl_DecrRefCount(ad);
	if (status != 0) {
		Tcl_DecrRefCount(name);

		return(NULL);
	}

	return(name);
}

static int cvfs_index_compare(const void *tag, const void *entry) {
	return(memcmp(tag, ((const struct cvfs_index_entry *) entry)->tag, 16));
}

/* Index of path, or 0: its tag must be in the index, and the entry's name
 * must decrypt to path, which also rules out tag collisions */
static unsigned long cvfs_encrypted_lookup(const char *path, const unsigned char *index_key, const unsigned char *key,
    const struct cvfs_index_entry *entries, size_t count, const struct cvfs_data *data) {
	const struct cvfs_index_entry *entry;
	unsigned char tag[16];
	const unsigned char *name_bytes;
	Tcl_Size name_length;
	Tcl_Obj *name;
	int match;

	crypto_blake2b_keyed(tag, sizeof(tag), index_key, 32, (const unsigned char *) path, strlen(path));

	entry = bsearch(tag, entries, count, sizeof(*entries), cvfs_index_compare);
	if (entry == NULL) {
		return(0);
	}

	name = cvfs_name(&data[entry->index], key);
	if (name == NULL) {
		return(0);
	}

	name_bytes = Tcl_GetByteArrayFromObj(name, &name_length);
	match = ((size_t) name_length == strlen(path) && memcmp(name_bytes, path, (size_t) name_length) == 0);
	cvfs_free_plain(name);

	return(match ? entry->index : 0);
}
#    endif /* CVFS_ENCRYPTED */

#  endif /* !LOADED_CVFS_COMMON */}
puts ""

unset -nocomplain children
array set children [list]
for {set idx 1} {$idx < [llength $files]} {incr idx} {
	set file [lindex $files $idx]
	set shortfile [shorten_file $startdir $file]

	set index_of($shortfile) $idx
	if {[file isdirectory $file]} {
		set children($idx) [list]
	}
}

# Each entry's parent is the part of its name before the last slash; the
# start directory itself (index 1) has the empty name
for {set idx 2} {$idx < [llength $files]} {incr idx} {
	set shortfile [shorten_file $startdir [lindex $files $idx]]
	set parent [string range $shortfile 0 [expr {[string last "/" $shortfile] - 1}]]

	lappend children($index_of($parent)) $idx
}

# Every directory's children, one directory after another; each directory's
# entry gives where its list starts and how long it is
set child_list [list]
foreach idx [lsort -integer [array names children]] {
	set first_child($idx) [llength $child_list]
	lappend child_list {*}$children($idx)
}
if {[llength $child_list] == 0} {
	set child_list [list 0]
}

puts "static const unsigned long ${code_tag}_children\[\] = {"
for {set start 0} {$start < [llength $child_list]} {incr start 16} {
	puts "\t[join [lrange $child_list $start [expr {$start + 15}]] {, }],"
}
puts "};"
puts ""

puts "static struct cvfs_data ${code_tag}_data\[\] = {"
puts "\t{"
puts "\t\t/* Index 0 cannot be used because we use the value 0 to represent failure */"
puts "\t\t.name  = NULL,"
puts "\t\t.index = 0,"
puts "\t\t.type  = 0,"
puts "\t\t.size  = 0,"
puts "\t\t.size_inflated = 0,"
puts "\t\t.mtime = 0,"
puts "\t\t.data  = NULL,"
puts "\t\t.free  = 0,"
puts "\t\t.name_box = NULL,"
puts "\t\t.name_box_size = 0,"
puts "\t\t.first_child = 0,"
puts "\t\t.num_children = 0,"
puts "\t},"
for {set idx 1} {$idx < [llength $files]} {incr idx} {
	set file [lindex $files $idx]
	set shortfile [shorten_file $startdir $file]

	unset -nocomplain finfo type
	file stat $file finfo

	switch -- $finfo(type) {
		"file" {
			set fd [open $file]
			fconfigure $fd -translation binary
			set data [expr {
				$compress ?  [zlib compress [read $fd]] : [read $fd]
			}]
			set size [string length $data]
			set size_inflated $finfo(size)

			close $fd

			if {$encrypt} {
				set data [$data_key encrypt $data -ad [data_ad $size_inflated $shortfile]]
				set size [string length $data]
				set type "CVFS_FILETYPE_FILE | CVFS_FILETYPE_ENCRYPTED_FILE"
			} else {
				set type "CVFS_FILETYPE_FILE"
			}
			set data "(unsigned char *) [stringify $data]"

			if {$compress} {
				set type "$type | CVFS_FILETYPE_COMPRESSED_FILE"
			}
		}
		"directory" {
			set type "CVFS_FILETYPE_DIR"
			set data "NULL"
			set size 0
			set size_inflated 0
		}
	}

	# Clamped to SOURCE_DATE_EPOCH when set, so builds can be reproducible
	set mtime $finfo(mtime)
	if {[info exists ::env(SOURCE_DATE_EPOCH)] && $mtime > $::env(SOURCE_DATE_EPOCH)} {
		set mtime $::env(SOURCE_DATE_EPOCH)
	}

	if {$encrypt} {
		set name "NULL"
		set name_box [$data_key encrypt [encoding convertto utf-8 $shortfile] -ad [name_ad $idx]]
		set name_box_size [string length $name_box]
		set name_box "(unsigned char *) [stringify $name_box]"
	} else {
		set name [cname $shortfile]
		set name_box "NULL"
		set name_box_size 0
	}

	puts "\t{"
	puts "\t\t.name  = $name,"
	puts "\t\t.index = $idx,"
	puts "\t\t.type  = $type,"
	puts "\t\t.size  = $size,"
	puts "\t\t.size_inflated = $size_inflated,"
	puts "\t\t.mtime = $mtime,"
	puts "\t\t.data  = $data,"
	puts "\t\t.free  = 0,"
	puts "\t\t.name_box = $name_box,"
	puts "\t\t.name_box_size = $name_box_size,"
	if {[info exists children($idx)]} {
		puts "\t\t.first_child = $first_child($idx),"
		puts "\t\t.num_children = [llength $children($idx)],"
	} else {
		puts "\t\t.first_child = 0,"
		puts "\t\t.num_children = 0,"
	}
	puts "\t},"
}
puts "};"
puts ""

if {$encrypt} {
	puts "static const unsigned char ${code_tag}_key\[32\] = [cbytes [$data_key export]];"
	puts "static const unsigned char ${code_tag}_index_key\[32\] = [cbytes [$index_key export]];"
	puts ""

	set tags [list]
	for {set idx 1} {$idx < [llength $files]} {incr idx} {
		set shortfile [shorten_file $startdir [lindex $files $idx]]
		set tag [$index_key mac [encoding convertto utf-8 $shortfile] -size 16]

		lappend tags [list [binary encode hex $tag] $tag $idx]
	}

	# Sorted as bsearch with memcmp expects: lower-case hex sorts as the bytes do
	puts "static const struct cvfs_index_entry ${code_tag}_index\[\] = {"
	foreach entry [lsort -index 0 $tags] {
		puts "\t{[cbytes [lindex $entry 1]], [lindex $entry 2]},"
	}
	puts "};"
	puts ""

	puts "static unsigned long ${code_tag}_lookup_index(const char *path) {"
	puts "\treturn(cvfs_encrypted_lookup(path, ${code_tag}_index_key, ${code_tag}_key, ${code_tag}_index,"
	puts "\t    sizeof(${code_tag}_index) / sizeof(${code_tag}_index\[0\]), ${code_tag}_data));"
	puts "}"
	puts ""

	$index_key destroy
} else {
	puts "static unsigned long ${code_tag}_lookup_index(const char *path) {"
	puts "\tswitch (cvfs_hash((unsigned char *) path)) {"

	for {set idx 1} {$idx < [llength $files]} {incr idx} {
		set file [lindex $files $idx]
		set shortfile [shorten_file $startdir $file]
		set hash [cvfs_hash $shortfile]

		lappend indexes_per_hash($hash) [list $shortfile $idx]
	}

	foreach hash [lsort -integer [array names indexes_per_hash]] {
		set idx_list $indexes_per_hash($hash)

		puts "\t\tcase $hash:"

		if {[llength $idx_list] == 1} {
			set idx [lindex $idx_list 0 1]

			puts "\t\t\treturn($idx);"
		} else {
			foreach idx_ent $idx_list {
				set shortfile [lindex $idx_ent 0]
				set idx [lindex $idx_ent 1]

				puts "\t\t\tif (strcmp(path, [cname $shortfile]) == 0) return($idx);"
			}
			puts "\t\t\tbreak;"
		}
	}

	puts "\t}"
	puts "\treturn(0);"
	puts "}"
	puts ""
}

puts "static struct cvfs_data *${code_tag}_getData(const char *path, unsigned long index) {"
puts "\tif (path != NULL) {"
puts "\t\tindex = ${code_tag}_lookup_index(path);"
puts "\t}"
puts ""
puts "\tif (index == 0) {"
puts "\t\treturn(NULL);"
puts "\t}"
puts ""
if {!$encrypt} {
	puts "\tif (path != NULL) {"
	puts "\t\tif (strcmp(path, ${code_tag}_data\[index\].name) != 0) {"
	puts "\t\t\treturn(NULL);"
	puts "\t\t}"
	puts "\t}"
	puts ""
}
puts "\treturn(&${code_tag}_data\[index\]);"
puts "}"
puts ""

puts "static unsigned long ${code_tag}_getChildren(const char *path, unsigned long *outbuf, unsigned long outbuf_count) {"
puts "\tunsigned long index;"
puts "\tunsigned long num_children;"
puts ""
puts "\tindex = ${code_tag}_lookup_index(path);"
puts "\tif (index == 0) {"
puts "\t\treturn(0);"
puts "\t}"
puts ""
puts "\tif ((${code_tag}_data\[index\].type & CVFS_FILETYPE_DIR) == 0) {"
puts "\t\treturn(0);"
puts "\t}"
puts ""
if {!$encrypt} {
	puts "\tif (strcmp(path, ${code_tag}_data\[index\].name) != 0) {"
	puts "\t\treturn(0);"
	puts "\t}"
	puts ""
}
puts "\tnum_children = ${code_tag}_data\[index\].num_children;"
puts "\tif (outbuf == NULL) {"
puts "\t\treturn(num_children);"
puts "\t}"
puts ""
puts "\tif (num_children > outbuf_count) {"
puts "\t\tnum_children = outbuf_count;"
puts "\t}"
puts ""
puts "\tmemcpy(outbuf, &${code_tag}_children\[${code_tag}_data\[index\].first_child\], num_children * sizeof(*outbuf));"
puts ""
puts "\treturn(num_children);"
puts "}"
puts ""

puts "#  ifdef CVFS_MAKE_LOADABLE"

set fd [open "cvfs_data.c"]
puts [read $fd]
close $fd

puts "static cmd_getData_t *getCmdData(const char *hashkey) {"
puts "\treturn(${code_tag}_getData);"
puts "}"
puts ""
puts "static cmd_getChildren_t *getCmdChildren(const char *hashkey) {"
puts "\treturn(${code_tag}_getChildren);"
puts "}"
puts ""
puts "static const unsigned char *getCmdKey(const char *hashkey) {"
if {$encrypt} {
	puts "\treturn(${code_tag}_key);"
} else {
	puts "\treturn(NULL);"
}
puts "}"
puts ""

puts "int Cvfs_data_${hashkey}_Init(Tcl_Interp *interp) {"
puts "\tTcl_Command tclCreatComm_ret;"
puts "\tint tclPkgProv_ret;"
puts ""
puts "#ifdef USE_TCL_STUBS"
puts "\tif (!Tcl_InitStubs(interp, TCL_VERSION, 0)) {"
puts "#else"
puts "\tif (!Tcl_PkgRequire(interp, \"Tcl\", TCL_VERSION, 0)) {"
puts "#endif /* USE_TCL_STUBS */"
puts "\t\treturn(TCL_ERROR);"
puts "\t}"
puts ""
puts "\ttclCreatComm_ret = Tcl_CreateObjCommand(interp, \"::vfs::cvfs::data::${hashkey}::getMetadata\", getMetadata, NULL, NULL);"
puts "\tif (!tclCreatComm_ret) {"
puts "\t\treturn(TCL_ERROR);"
puts "\t}"
puts ""
puts "\ttclCreatComm_ret = Tcl_CreateObjCommand(interp, \"::vfs::cvfs::data::${hashkey}::getData\", getData, NULL, NULL);"
puts "\tif (!tclCreatComm_ret) {"
puts "\t\treturn(TCL_ERROR);"
puts "\t}"
puts ""
puts "\ttclCreatComm_ret = Tcl_CreateObjCommand(interp, \"::vfs::cvfs::data::${hashkey}::getChildren\", getChildren, NULL, NULL);"
puts "\tif (!tclCreatComm_ret) {"
puts "\t\treturn(TCL_ERROR);"
puts "\t}"
puts ""
if {$encrypt} {
	puts "\ttclCreatComm_ret = Tcl_CreateObjCommand(interp, \"::vfs::cvfs::data::${hashkey}::open\", openFile, NULL, NULL);"
	puts "\tif (!tclCreatComm_ret) {"
	puts "\t\treturn(TCL_ERROR);"
	puts "\t}"
	puts ""
}
puts "\ttclPkgProv_ret = Tcl_PkgProvide(interp, \"vfs::cvfs::data::${hashkey}\", \"1.0\");"
puts ""
puts "\treturn(tclPkgProv_ret);"
puts "}"
puts "#  endif /* CVFS_MAKE_LOADABLE */"

puts "#endif /* !$cpp_tag */"

if {$encrypt} {
	$data_key destroy
}
