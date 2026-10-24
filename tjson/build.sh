
# BuildCompatible: KitCreator

version='1.0.26'
url="https://github.com/jerily/tjson/archive/refs/tags/v${version}.tar.gz"
sha256='b5155a804f79666d3059d83ac875e6461e8bc16ae0280d54629140b85f87830d'

case "${CONFIGUREEXTRA}" in
    *--enable-symbols*)
	tjson_build_type=Debug
	;;
    *)
	tjson_build_type=Release
	;;
esac

configure() {
	stub_lib="$(ls "${KITCREATOR_DIR}"/tcl/inst/lib/libtclstub*.a)"
	cmake . \
	      -DCMAKE_INSTALL_PREFIX="${installdir}" \
	      -DTCL_STUB_LIBRARY="${stub_lib}" \
	      -DTCL_INCLUDE_PATH="${KITCREATOR_DIR}/tcl/inst/include" \
	      -DCMAKE_BUILD_TYPE="${tjson_build_type}"
}

build() {
	cmake --build . --config "${tjson_build_type}"
}

install() {
	cmake --install . --config "${tjson_build_type}" --prefix "${installdir}"
}

postinstall() {
	rm -f "${installdir}"/lib/*/libtjson.dll.a ;# Prevent inadvertent link on MSys2
}
