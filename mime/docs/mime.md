# mime

MIME type lookup, media type parsing/formatting, and RFC 2047 word
encoding/decoding.

Wraps Go's standard `mime` package.

## Synopsis

```tcl
package require mime2

mime type extension
mime extensions type
mime add extension type
mime parse value
mime format type ?key value ...?
mime encode ?-q? charset string
mime decode word
mime decodeheader string
```

## Commands

### mime type *extension*

Returns the MIME type associated with the file extension *extension*.
The extension should begin with a leading dot (e.g. `.html`).
Returns an empty string if the extension is unknown.

Text types include `charset=utf-8` by default.

```tcl
mime type .html    ;# text/html; charset=utf-8
mime type .png     ;# image/png
mime type .json    ;# application/json
mime type .xyzzy   ;# {} (empty string)
```

### mime extensions *type*

Returns a list of file extensions associated with the MIME type *type*.
Each extension includes a leading dot. Returns an empty list if the
type is unknown.

```tcl
mime extensions text/html          ;# .html .htm ...
mime extensions application/json   ;# .json
```

### mime add *extension* *type*

Registers a custom mapping from *extension* to *type*. The extension
should begin with a leading dot. Subsequent calls to `mime type` will
return the registered type.

```tcl
mime add .myformat application/x-myformat
mime type .myformat   ;# application/x-myformat
```

### mime parse *value*

Parses a media type value (e.g. a Content-Type header) per RFC 1521.
Returns a Tcl dictionary with a `mediatype` key and any additional
parameter keys.

```tcl
set d [mime parse "text/html; charset=utf-8"]
dict get $d mediatype   ;# text/html
dict get $d charset     ;# utf-8

set d [mime parse "multipart/form-data; boundary=----abc"]
dict get $d mediatype   ;# multipart/form-data
dict get $d boundary    ;# ----abc
```

### mime format *type* ?*key* *value* ...?

Formats a media type string conforming to RFC 2045 and RFC 2616.
The type and parameter names are written in lowercase. Key-value
pairs are optional and specify parameters.

```tcl
mime format text/html                        ;# text/html
mime format text/html charset utf-8          ;# text/html; charset=utf-8
mime format multipart/mixed boundary xyzzy   ;# multipart/mixed; boundary=xyzzy
```

### mime encode ?**-q**? *charset* *string*

Encodes *string* as an RFC 2047 encoded-word using the given *charset*.
Uses base64 encoding by default. Pass **-q** for Q-encoding.

Pure ASCII strings that need no encoding are returned unchanged.

```tcl
mime encode utf-8 "Héllo"        ;# =?utf-8?b?SMOpbGxv?=
mime encode -q utf-8 "Héllo"     ;# =?utf-8?q?H=C3=A9llo?=
mime encode utf-8 Hello          ;# Hello (no encoding needed)
```

### mime decode *word*

Decodes a single RFC 2047 encoded-word.

```tcl
mime decode "=?utf-8?b?SMOpbGxv?="    ;# Héllo
mime decode "=?utf-8?q?H=C3=A9llo?="  ;# Héllo
```

### mime decodeheader *string*

Decodes an entire header string that may contain a mix of RFC 2047
encoded-words and plain text.

```tcl
mime decodeheader "=?utf-8?b?SMOpbGxv?= World"   ;# Héllo World
mime decodeheader "Just plain text"                ;# Just plain text
```
