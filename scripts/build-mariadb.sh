#!/bin/bash
# MariaDB Connector/C (shared libmariadb + headers) for each architecture into
# $STAGE/<arch>/mariadb. Needs build-openssl.sh and build-compression.sh first.
#
# Every sign-in plugin and the zstd compression plugin are built into the library (STATIC), so
# nothing is ever loaded from a plugin directory at run time. Kerberos (auth_gssapi_client) uses
# Apple's GSS.framework through the same header shims as libpq (decision D4). LGPL-2.1: it ships
# as its own dynamic library, unmodified.
. "$(dirname "$0")/common.sh"
use_cmake

shims="$ROOT/scripts/shims"
plugins=(MYSQL_NATIVE_PASSWORD CACHING_SHA2_PASSWORD SHA256_PASSWORD CLIENT_ED25519 PARSEC
         DIALOG MYSQL_CLEAR_PASSWORD AUTH_GSSAPI_CLIENT ZSTD)

for arch in "${ARCHS[@]}"; do
  log "MariaDB Connector/C $(version mariadb-connector-c) for $arch"
  src="$(unpack mariadb-connector-c "$arch")"
  build="$src/_build"
  prefix="$STAGE/$arch/mariadb"; rm -rf "$prefix"
  ssl="$STAGE/$arch/openssl"; zstd="$STAGE/$arch/zstd"
  plugin_flags=()
  for plugin in "${plugins[@]}"; do plugin_flags+=("-DCLIENT_PLUGIN_$plugin=STATIC"); done
  cmake -S "$src" -B "$build" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_OSX_SYSROOT="$SDKROOT" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local;/opt/local" \
    -DWITH_SSL=OPENSSL -DOPENSSL_ROOT_DIR="$ssl" -DOPENSSL_USE_STATIC_LIBS=OFF \
    -DWITH_EXTERNAL_ZLIB=ON \
    -DZSTD_INCLUDE_DIRS="$zstd/include" -DZSTD_LIBRARIES="$zstd/lib/libzstd.dylib" \
    -DGSSAPI_FLAVOR=HEIMDAL -DGSSAPI_LIBS="-framework GSS" -DGSSAPI_INCS="$shims" \
    -DWITH_CURL=OFF -DWITH_UNIT_TESTS=OFF -DWITH_ICONV=OFF \
    -DCLIENT_PLUGIN_MYSQL_OLD_PASSWORD=OFF \
    "${plugin_flags[@]}" > "$src/configure.log"
  cmake --build "$build" -j"$JOBS" > "$src/build.log"
  cmake --install "$build" > "$src/install.log"
  lib="$(find "$prefix" -name 'libmariadb.3.dylib' | head -1)"
  [ -n "$lib" ] || die "libmariadb.3.dylib not installed"
  lipo -archs "$lib" | grep -qx "$arch" || die "libmariadb is not $arch"
  echo "  $lib"
  grep -E "Plugin|SSL|GSSAPI|ZSTD" "$src/configure.log" | sed 's/^/  /' | head -20
done
