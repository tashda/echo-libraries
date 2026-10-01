#!/bin/bash
# OpenSSL (shared libssl + libcrypto, headers) for each architecture into $STAGE/<arch>/openssl.
. "$(dirname "$0")/common.sh"

for arch in "${ARCHS[@]}"; do
  log "OpenSSL $(version openssl) for $arch"
  src="$(unpack openssl "$arch")"
  prefix="$STAGE/$arch/openssl"
  destdir="$WORK/$arch/openssl-dest"; rm -rf "$destdir"
  case "$arch" in arm64) target=darwin64-arm64-cc ;; x86_64) target=darwin64-x86_64-cc ;; esac
  (
    cd "$src"
    # OPENSSLDIR is where OpenSSL would look for a default CA bundle. Echo never relies on it
    # (it passes the Keychain trust bundle or the user's CA file explicitly); /etc/ssl is macOS's.
    # No $PREFIX_MAP: OpenSSL compiles in its own tree with relative paths, so __FILE__ is already
    # neutral, and it records its compiler flags in the library ("compiler: …"), path and all.
    ./Configure "$target" shared no-tests no-docs \
      --prefix="$NEUTRAL_PREFIX/openssl" --libdir=lib --openssldir=/etc/ssl \
      -isysroot "$SDKROOT" -mmacosx-version-min="$DEPLOYMENT_TARGET" "$LINK_PAD" > "$src/configure.log"
    make -j"$JOBS" build_libs > "$src/build.log"
    make install_dev DESTDIR="$destdir" > "$src/install.log"
  )
  take_staged openssl "$arch" "$destdir"
  point_at_stage "$prefix/lib" "$arch"
  lipo -archs "$prefix/lib/libssl.3.dylib" | grep -qx "$arch" || die "libssl is not $arch"
  echo "  $prefix/lib: $(ls "$prefix/lib" | tr '\n' ' ')"
done
