#
# This script is designed to be called by jobs in .github/workflows/create-release.yml
#

package require http
package require tls
package require json
package require tcl::chan::string

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

set release_query {
    {
        "tag_name": "@TAG@",
        "target_commitish": "main",
        "name": "@NAME@"
    }
}
set release_query [string map [list @TAG@  $tag_name \
                                    @NAME@ "TclMonster kits ([clock format [clock seconds] -format {%Y-%m-%d}])"] \
                       $release_query]

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

set release_info [::json::json2dict [http::data $response]]
set upload_url [string map [list \{?name,label\} {}] [dict get $release_info upload_url]]
set release_id [dict get $release_info id]

set Linux_assets   [list]
set Windows_assets [list]
set macOS_assets   [list]
foreach kitfile [lsort [glob kitcreator-*-kits/*]] {
    puts -nonewline "Uploading \"$kitfile\"... "
    set kitchan [open $kitfile]
    fconfigure $kitchan -translation binary
    set query [http::formatQuery name [file tail $kitfile]]
    set response [http::geturl ${upload_url}?${query} -keepalive true -headers $headers \
                      -type application/octet-stream \
                      -querychannel $kitchan]

    if {[http::status $response] != "ok" || [http::ncode $response] != 201} {
        puts "Failed!"
        puts stderr [http::data $response]
        exit 1
    }

    set asset_info [::json::json2dict [http::data $response]]
    switch -glob -- $kitfile {
        *linux*   {set kit_os Linux}
        *windows* {set kit_os Windows}
        *macos*   {set kit_os macOS}
        default   {set kit_os {}}
    }
    if {$kit_os ne {}} {
        lappend ${kit_os}_assets [list [file tail $kitfile] $asset_info]
    }
    puts "Success."
    close $kitchan
    http::cleanup $response
}

set package_map [dict create]
foreach kc_pkgs_file [glob kitcreator-*-kc_packages/*] {
    set key [file rootname [file tail $kc_pkgs_file]]
    set fd  [open $kc_pkgs_file]
    set value  [list {*}[string trim [read $fd]]]
    close $fd

    set kitdll_index [lsearch $value kitdll]
    if {$kitdll_index ne -1} {
        set value [lreplace $value $kitdll_index $kitdll_index]    ;# Kitdll is not an actual extension
    }

    dict set package_map "$key" $value
}

proc formatSize {sizeInBytes} {
    set sizes [list "bytes" "KB" "MB" "GB" "TB"]
    set unit "bytes"
    set index 0

    while {$sizeInBytes >= 1024 && $index < [llength $sizes] - 1} {
        set sizeInBytes [expr {$sizeInBytes / 1024.0}]
        set index [expr {$index + 1}]
        set unit [lindex $sizes $index]
    }

    return [format "%.2f %s" $sizeInBytes $unit]
}


set release_body {
### Tcl kits available for Linux, macOS, and Windows.

This release includes kits with and without Tk; also included are minimal kits with only
the base dependencies; and lastly, the SDK provides shared libraries that may be used to
conveniently build extensions (without compiling Tcl/Tk) or to link a working Tcl interpreter
into any application.

}

set hdr_template {
#### @KIT_OS@

| File | Version | Arch.  | Tk  | SDK | Extensions | Size |
| :--- | ---     | ---    | --- | --- | ---        | ---: |
}

set row_template {| [@FILE@](@URL@) | @VERSION@ | @ARCH@ | @HAS_TK@ | @HAS_SDK@ | @EXTENSIONS@ | @SIZE@ |
}

foreach kit_os {Linux macOS Windows} {
    append release_body [string map [list @KIT_OS@ $kit_os] $hdr_template]
    foreach pair [set ${kit_os}_assets] {
        if {$pair eq {}} {
            continue
        }
        set asset [lindex $pair 0]
        set asset_info [lindex $pair 1]
        lassign [regexp -inline -- {((?:lib)?tclkit(?:sh|-sdk)?)-([0-9.]+)-([^-]+)-} $asset] \
            _ asset_prefix asset_version asset_arch

        set has_tk  {}
        set has_sdk {}
        switch -- $asset_prefix {
            tclkit {
                set has_tk ✔
            }
            tclkitsh {
            }
            libtclkit-sdk {
                set has_tk ✔
                set has_sdk ✔
            }
        }
        append release_body [string map [list \
                                             @FILE@       $asset \
                                             @URL@        [dict get $asset_info browser_download_url] \
                                             @VERSION@    $asset_version \
                                             @ARCH@       $asset_arch \
                                             @HAS_TK@     $has_tk \
                                             @HAS_SDK@    $has_sdk \
                                             @EXTENSIONS@ [dict get $package_map $asset] \
                                             @SIZE@       [formatSize [dict get $asset_info size]]] $row_template]
    }
}

set release_query [tcl::chan::string [string map [list @BODY@ [string map {\n \\n} $release_body]] {{"body": "@BODY@"}}]]
set response [http::geturl $release_url/$release_id -headers $headers \
                  -method PATCH \
                  -type application/json \
                  -querychannel $release_query]

if {[http::status $response] != "ok" || [http::ncode $response] != 200} {
    puts stderr "Failed to update release body"
    puts stderr "Request: \"$release_query\""
    puts stderr "Response: \"[http::data $response]\""
    exit 1
}
