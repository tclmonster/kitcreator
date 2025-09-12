
# BuildCompatible: KitCreator

version='1.0.25'
url="https://github.com/jerily/tjson/archive/refs/tags/v${version}.tar.gz"
sha256='43644f5f71b6a073d80e8a9dcb32a9c8db0d583f7d2ea1486daa915354492b1b'

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
