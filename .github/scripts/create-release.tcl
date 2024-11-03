#
# This script is designed to be called by jobs in .github/workflows/create-release.yml
#

package require http
package require tls
package require json

http::register https 443 [list ::tls::socket -require true]

if {! [info exists env(GH_TOKEN)]} {
    puts stderr "\"env.GH_TOKEN\" must be set to \"secrets.GITHUB_TOKEN\""
    exit 1
}

if {[llength $argv] < 4} {
    puts stderr "Usage: create-release.tcl api_url owner repo tag_name"
    exit 1
}

lassign $argv api_url owner repo tag_name

set release_body {
    Tcl kits available for Linux, macOS, and Windows.

    The \"tclkitsh\" kits are command-line only; \"tclkit\" kits contain Tk as a shared library and
    so they may include a GUI if desired; \"libtclkit-sdk\" archives may be extracted and used to link
    extensions against (without having to compile Tcl/Tk), or they may be linked into an application
    to provide a static Tcl/Tk interpreter. Kits with the \"minimal\" suffix only contain base Tcl/Tk
    libraries.
}

set release_query {
    {
        "tag_name": "_TAG_",
        "target_commitish": "main",
        "name": "_NAME_",
        "body": "_BODY_"
    }
}
set release_query [string map [list _TAG_  $tag_name \
                                    _NAME_ "Monster kits ([clock format [clock seconds] -format {%Y-%m-%d}])" \
                                    _BODY_ [regsub -all {\n} $release_body {\\n}]] $release_query]

set release_url $api_url/repos/$owner/$repo/releases
set headers  [list Accept application/vnd.github+json Authorization "Bearer $env(GH_TOKEN)" X-GitHub-Api-Version 2022-11-28]
set response [http::geturl $release_url -keepalive true -headers $headers \
                  -type application/json \
                  -query $release_query]

if {[http::status $response] != "ok"} {
    puts stderr "Error retrieving URL: \"[http::error $response]\""
    exit 1
}

if {[http::ncode $response] != 201} {
    puts stderr "Failed to create release: \"[http::data $response]\""
    exit 1
}

set upload_url [string map [list \{?name,label\} {}] \
                    [dict get [::json::json2dict [http::data $response]] upload_url]]

foreach kitfile [glob kitcreator-*-kits/*] {
    puts -nonewline "Uploading \"$kitfile\"... "
    set query [http::formatQuery name [file tail $kitfile]]
    set kitchan [open $kitfile]
    fconfigure $kitchan -translation binary

    set response [http::geturl ${upload_url}?${query} -keepalive true -headers $headers \
                      -type application/octet-stream \
                      -querychannel $kitchan]

    if {[http::status $response] != "ok" || [http::ncode $response] != 201} {
        puts "Failed!"
        puts stderr [http::data $response]
        exit 1
    }
    puts "Success."
    close $kitchan
    http::cleanup $response
}
