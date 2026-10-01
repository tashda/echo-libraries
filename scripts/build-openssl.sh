#!/bin/bash
# OpenSSL (shared libssl + libcrypto, headers) for each architecture into $STAGE/<arch>/openssl.
. "$(dirname "$0")/common.sh"

for arch in "${ARCHS[@]}"; do
  log "OpenSSL $(version openssl) for $arch"
  src="$(unpack openssl "$arch")"
  prefix="$STAGE/$arch/openssl"
  rm -rf "$prefix"
  case "$arch" in arm64) target=darwin64-arm64-cc ;; x86_64) target=darwin64-x86_64-cc ;; esac
  (
    cd "$src"
    # OPENSSLDIR is where OpenSSL would look for a default CA bundle. Echo never relies on it
    # (it passes the Keychain trust bundle or the user's CA file explicitly); /etc/ssl is macOS's.
    ./Configure "$target" shared no-tests no-docs \
      --prefix="$prefix" --libdir=lib --openssldir=/etc/ssl \
      -isysroot "$SDKROOT" -mmacosx-version-min="$DEPLOYMENT_TARGET" > "$src/configure.log"
    make -j"$JOBS" build_libs > "$src/build.log"
    make install_dev > "$src/install.log"
  )
  lipo -archs "$prefix/lib/libssl.3.dylib" | grep -qx "$arch" || die "libssl is not $arch"
  echo "  $prefix/lib: $(ls "$prefix/lib" | tr '\n' ' ')"
done
